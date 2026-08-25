<?php

namespace App\Console\Commands;

use Carbon\CarbonImmutable;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Repairs staff_attendance rows whose created_at was written through a
 * connection that wasn't pinned to UTC.
 *
 * staff_attendance.created_at is a MySQL TIMESTAMP, which the server
 * converts using the *session* time zone. This app pins that to +00:00
 * (config/database.php), but a writer that didn't - a host whose .env has no
 * DB_TIMEZONE, an import run through the mysql CLI, phpMyAdmin - hands MySQL
 * a correct UTC datetime that then gets re-read as Manila local and stored
 * eight hours early. The punch times then read back eight hours behind
 * reality, which pushes a morning time-in onto the previous evening and its
 * time-out onto the following morning - so the pair straddles midnight, the
 * day never closes, and payroll counts it as zero hours.
 *
 * Ground truth for the repair is each punch's selfie filename: it's stamped
 * from the app's own clock at the moment of the punch (see
 * AttendancePhotoStorage), in APP_TIMEZONE rather than through the database,
 * so it survives the skew untouched. That also makes this command safely
 * repeatable - once a row is correct its measured skew is zero and it's left
 * alone.
 */
class FixAttendanceTimezoneSkew extends Command
{
    protected $signature = 'attendance:fix-timezone
        {--apply : Write the correction (default is a dry run that changes nothing)}
        {--include-photoless : Also shift rows that have no selfie to measure against, using the skew proven by the rows that do}
        {--revert : Restore created_at from the backup table taken by the last --apply}';

    protected $description = 'Detect and repair staff_attendance punch times stored through a non-UTC connection';

    private const BACKUP_TABLE = 'staff_attendance_bak_tzfix';

    /** Ignore sub-second noise when grouping measured skews. */
    private const TOLERANCE_SECONDS = 90;

    public function handle(): int
    {
        if (! Schema::hasTable('staff_attendance')) {
            $this->error('staff_attendance table missing. Run: php artisan migrate');

            return self::FAILURE;
        }

        if ($this->option('revert')) {
            return $this->revert();
        }

        $rows = DB::table('staff_attendance')
            ->select('id', 'created_at', 'photo_url')
            ->orderBy('id')
            ->get();

        if ($rows->isEmpty()) {
            $this->info('No attendance rows to check.');

            return self::SUCCESS;
        }

        /** @var array<int, list<int>> $bySkew  skew in seconds => row ids */
        $bySkew = [];
        $photoless = [];

        foreach ($rows as $row) {
            $stampedAt = $this->photoStampedAt((string) ($row->photo_url ?? ''));
            if ($stampedAt === null) {
                $photoless[] = (int) $row->id;

                continue;
            }

            $stored = CarbonImmutable::parse((string) $row->created_at, 'UTC');
            $skew = $stampedAt->getTimestamp() - $stored->getTimestamp();
            $bucket = (int) (round($skew / self::TOLERANCE_SECONDS) * self::TOLERANCE_SECONDS);
            $bySkew[$bucket][] = (int) $row->id;
        }

        if ($bySkew === []) {
            $this->error('No punch has a selfie to measure against - nothing can be verified, so nothing will be changed.');

            return self::FAILURE;
        }

        ksort($bySkew);
        $this->line('Measured skew (selfie time minus stored time):');
        foreach ($bySkew as $seconds => $ids) {
            $this->line(sprintf(
                '  %+.2f hours  %d row(s)%s',
                $seconds / 3600,
                count($ids),
                $seconds === 0 ? '  <- already correct' : '',
            ));
        }
        if ($photoless !== []) {
            $this->line('  '.count($photoless).' row(s) have no selfie to measure');
        }

        $skewed = array_filter($bySkew, static fn (int $seconds): bool => $seconds !== 0, ARRAY_FILTER_USE_KEY);
        if ($skewed === []) {
            $this->info('Every measurable punch is already correct. Nothing to do.');

            return self::SUCCESS;
        }

        if (count($skewed) > 1) {
            $this->error('Rows are skewed by more than one amount - this needs a look by hand rather than a blanket shift.');

            return self::FAILURE;
        }

        $shiftSeconds = (int) array_key_first($skewed);
        $targetIds = $skewed[$shiftSeconds];

        if ($this->option('include-photoless') && $photoless !== []) {
            $targetIds = array_merge($targetIds, $photoless);
            $this->warn(count($photoless).' unmeasurable row(s) will be shifted on the strength of the rows that could be measured.');
        }

        $this->newLine();
        $this->line(sprintf(
            'Correction: shift %d row(s) by %+.2f hours.',
            count($targetIds),
            $shiftSeconds / 3600,
        ));
        $this->sampleTable($targetIds, $shiftSeconds);

        if (! $this->option('apply')) {
            $this->newLine();
            $this->warn('Dry run - nothing was written. Re-run with --apply once the sample above looks right.');

            return self::SUCCESS;
        }

        $this->backup();

        $shifted = 0;
        foreach (array_chunk($targetIds, 500) as $chunk) {
            $shifted += DB::table('staff_attendance')
                ->whereIn('id', $chunk)
                ->update([
                    'created_at' => DB::raw("DATE_ADD(created_at, INTERVAL {$shiftSeconds} SECOND)"),
                ]);
        }

        $this->info("Shifted {$shifted} row(s). Backup of the originals: ".self::BACKUP_TABLE);
        $this->line('Undo with: php artisan attendance:fix-timezone --revert');

        return self::SUCCESS;
    }

    /**
     * Punch selfies are named att_YmdHis_random.ext, stamped in APP_TIMEZONE
     * at the moment of the punch.
     */
    private function photoStampedAt(string $photoUrl): ?CarbonImmutable
    {
        if ($photoUrl === '' || ! preg_match('/att_(\d{8})(\d{6})_/', $photoUrl, $match)) {
            return null;
        }

        try {
            $at = CarbonImmutable::createFromFormat('YmdHis', $match[1].$match[2], config('app.timezone'));
        } catch (\Throwable) {
            return null;
        }

        return $at === false ? null : $at;
    }

    /**
     * @param  list<int>  $ids
     */
    private function sampleTable(array $ids, int $shiftSeconds): void
    {
        $sample = DB::table('staff_attendance')
            ->join('users', 'users.id', '=', 'staff_attendance.user_id')
            ->whereIn('staff_attendance.id', array_slice($ids, -5))
            ->orderBy('staff_attendance.id')
            ->get(['users.full_name', 'staff_attendance.event_type', 'staff_attendance.created_at']);

        $timezone = (string) config('app.timezone');

        $this->table(
            ['Staff', 'Event', 'Shows now', 'Will show'],
            $sample->map(function (object $row) use ($shiftSeconds, $timezone): array {
                $stored = CarbonImmutable::parse((string) $row->created_at, 'UTC');

                return [
                    $row->full_name,
                    $row->event_type,
                    $stored->setTimezone($timezone)->format('d/m/Y g:i a'),
                    $stored->addSeconds($shiftSeconds)->setTimezone($timezone)->format('d/m/Y g:i a'),
                ];
            })->all(),
        );
    }

    private function backup(): void
    {
        DB::statement('DROP TABLE IF EXISTS '.self::BACKUP_TABLE);
        DB::statement('CREATE TABLE '.self::BACKUP_TABLE.' LIKE staff_attendance');
        DB::statement('INSERT INTO '.self::BACKUP_TABLE.' SELECT * FROM staff_attendance');
    }

    private function revert(): int
    {
        if (! Schema::hasTable(self::BACKUP_TABLE)) {
            $this->error('No backup table ('.self::BACKUP_TABLE.') - nothing to revert to.');

            return self::FAILURE;
        }

        $restored = DB::update(
            'UPDATE staff_attendance sa
             JOIN '.self::BACKUP_TABLE.' bak ON bak.id = sa.id
             SET sa.created_at = bak.created_at',
        );

        $this->info("Restored created_at on {$restored} row(s) from ".self::BACKUP_TABLE.'.');

        return self::SUCCESS;
    }
}
