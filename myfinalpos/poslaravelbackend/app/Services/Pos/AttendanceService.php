<?php



namespace App\Services\Pos;



use App\Support\Geofence;

use App\Support\PosHelpers;

use Illuminate\Support\Carbon;

use Illuminate\Support\Facades\DB;

use Illuminate\Support\Facades\Schema;



class AttendanceService

{

    public static function requiresGps(): bool

    {

        return filter_var(env('ATTENDANCE_REQUIRE_GPS', false), FILTER_VALIDATE_BOOLEAN);

    }

    /**

     * @return array{
     *     morning_accept_start: string,
     *     morning_official_start: string,
     *     morning_grace_end: string,
     *     morning_late_start: string,
     *     morning_cutoff: string,
     *     break_out_start: string,
     *     break_out_end: string,
     *     afternoon_accept_start: string,
     *     afternoon_on_time_end: string,
     *     afternoon_late_start: string,
     *     afternoon_cutoff: string,
     *     timeout_start: string,
     *     start_time: string,
     *     grace_minutes: int,
     *     late_after_time: string,
     *     lunch_out_time: string,
     *     lunch_out_start_time: string,
     *     afternoon_in_time: string,
     *     afternoon_in_start_time: string,
     *     afternoon_in_end_time: string,
     *     day_end_time: string,
     *     morning_absent_after_time: string,
     *     morning_in_end_time: string
     * }

     */

    public function schedule(): array

    {

        $settings = app(AppSettingsService::class)->read();

        $morningAcceptStart = $this->normalizeTime((string) $settings['attendance_morning_accept_start']);
        $morningOfficialStart = $this->normalizeTime((string) $settings['attendance_morning_official_start']);
        $morningGraceEnd = $this->normalizeTime((string) $settings['attendance_morning_grace_end']);
        $morningLateStart = $this->normalizeTime((string) $settings['attendance_morning_late_start']);
        $morningCutoff = $this->normalizeTime((string) $settings['attendance_morning_cutoff']);
        $breakOutStart = $this->normalizeTime((string) $settings['attendance_break_out_start']);
        $breakOutEnd = $this->normalizeTime((string) $settings['attendance_break_out_end']);
        $afternoonAcceptStart = $this->normalizeTime((string) $settings['attendance_afternoon_accept_start']);
        $afternoonOnTimeEnd = $this->normalizeTime((string) $settings['attendance_afternoon_on_time_end']);
        $afternoonLateStart = $this->normalizeTime((string) $settings['attendance_afternoon_late_start']);
        $afternoonCutoff = $this->normalizeTime((string) $settings['attendance_afternoon_cutoff']);
        $timeoutStart = $this->normalizeTime((string) $settings['attendance_timeout_start']);

        $graceMinutes = max(
            0,
            (int) Carbon::createFromFormat('H:i', $morningOfficialStart)
                ->diffInMinutes(Carbon::createFromFormat('H:i', $morningGraceEnd), false),
        );

        return [
            'morning_accept_start' => $morningAcceptStart,
            'morning_official_start' => $morningOfficialStart,
            'morning_grace_end' => $morningGraceEnd,
            'morning_late_start' => $morningLateStart,
            'morning_cutoff' => $morningCutoff,
            'break_out_start' => $breakOutStart,
            'break_out_end' => $breakOutEnd,
            'afternoon_accept_start' => $afternoonAcceptStart,
            'afternoon_on_time_end' => $afternoonOnTimeEnd,
            'afternoon_late_start' => $afternoonLateStart,
            'afternoon_cutoff' => $afternoonCutoff,
            'timeout_start' => $timeoutStart,
            'start_time' => $morningOfficialStart,
            'grace_minutes' => $graceMinutes,
            'late_after_time' => $morningLateStart,
            'lunch_out_time' => $breakOutEnd,
            'lunch_out_start_time' => $breakOutStart,
            'afternoon_in_time' => $afternoonAcceptStart,
            'afternoon_in_start_time' => $afternoonAcceptStart,
            'afternoon_in_end_time' => $afternoonOnTimeEnd,
            'day_end_time' => $timeoutStart,
            'morning_absent_after_time' => $morningCutoff,
            'morning_in_end_time' => $morningCutoff,
        ];

    }



    /**

     * @return array<int, array<string, mixed>>

     */

    public function dailyBoard(string $date, ?int $branchId = null): array

    {

        if (! Schema::hasTable('staff_attendance') || ! Schema::hasTable('users')) {

            return [];

        }



        [$start, $end] = $this->dayBoundsUtc($date);



        $userParams = [];

        $userBranchSql = '';

        if ($branchId !== null && $branchId > 0) {

            $userBranchSql = 'AND u.branch_id = ?';

            $userParams[] = $branchId;

        }



        $users = DB::select(

            "SELECT u.id, u.full_name, u.role, u.branch_id,

                    COALESCE(b.name, 'Unassigned') AS branch_name

             FROM users u

             LEFT JOIN branches b ON b.id = u.branch_id

             WHERE COALESCE(u.status, 1) = 1

             {$userBranchSql}

             ORDER BY u.full_name ASC",

            $userParams,

        );



        $eventParams = [$start, $end];

        $eventBranchSql = '';

        if ($branchId !== null && $branchId > 0) {

            $eventBranchSql = 'AND sa.branch_id = ?';

            $eventParams[] = $branchId;

        }



        $events = DB::select(

            "SELECT sa.*

             FROM staff_attendance sa

             WHERE sa.created_at BETWEEN ? AND ?

             {$eventBranchSql}

             ORDER BY sa.user_id ASC, sa.created_at ASC",

            $eventParams,

        );



        $byUser = [];

        foreach ($events as $event) {

            $byUser[(int) $event->user_id][] = $event;

        }



        $rows = [];

        foreach ($users as $user) {

            $userId = (int) $user->id;

            $userEvents = $byUser[$userId] ?? [];

            $summary = $this->summarizeDay($userEvents, $date);



            $rows[] = [

                'user_id' => $userId,

                'full_name' => (string) $user->full_name,

                'role' => (string) $user->role,

                'branch_id' => $user->branch_id !== null ? (int) $user->branch_id : null,

                'branch_name' => (string) $user->branch_name,

                ...$summary,

            ];

        }



        return $rows;

    }



    /**

     * @return array<string, mixed>

     */

    public function userStatus(int $userId, ?string $date = null): array

    {

        $date = $date ?? Carbon::today(self::DISPLAY_TIMEZONE)->format('Y-m-d');

        [$start, $end] = $this->dayBoundsUtc($date);



        $events = DB::select(

            'SELECT * FROM staff_attendance

             WHERE user_id = ? AND created_at BETWEEN ? AND ?

             ORDER BY created_at ASC',

            [$userId, $start, $end],

        );



        return $this->summarizeDay($events, $date);

    }



    /**

     * @return array<int, array<string, mixed>>

     */

    public function punctualityReport(string $startDate, string $endDate, ?int $branchId = null): array

    {

        $start = Carbon::parse($startDate)->startOfDay();

        $end = Carbon::parse($endDate)->startOfDay();

        if ($end->lt($start)) {

            [$start, $end] = [$end, $start];

        }



        $aggregates = [];



        for ($day = $start->copy(); $day->lte($end); $day->addDay()) {
            $date = $day->format('Y-m-d');

            if (! $this->dayHasClockEvents($date, $branchId)) {
                continue;
            }

            foreach ($this->dailyBoard($date, $branchId) as $row) {

                $userId = (int) $row['user_id'];

                if (! isset($aggregates[$userId])) {

                    $aggregates[$userId] = [

                        'user_id' => $userId,

                        'full_name' => (string) $row['full_name'],

                        'role' => (string) $row['role'],

                        'branch_name' => (string) $row['branch_name'],

                        'days_tracked' => 0,

                        'days_present' => 0,

                        'days_half_day' => 0,

                        'days_late' => 0,

                        'days_absent' => 0,

                    ];

                }



                $dailyStatus = (string) ($row['daily_status'] ?? 'in_progress');
                $morningStatus = (string) ($row['morning_session_status'] ?? 'not_in_yet');
                $afternoonStatus = (string) ($row['afternoon_session_status'] ?? 'not_in_yet');
                $aggregates[$userId]['days_tracked']++;

                match ($dailyStatus) {
                    'present' => $aggregates[$userId]['days_present']++,
                    'half_day' => $aggregates[$userId]['days_half_day']++,
                    'absent' => $aggregates[$userId]['days_absent']++,
                    default => null,
                };

                foreach ([$morningStatus, $afternoonStatus] as $sessionStatus) {
                    if ($sessionStatus === 'late') {
                        $aggregates[$userId]['days_late']++;
                    }
                }

            }

        }



        $rows = [];

        foreach ($aggregates as $aggregate) {

            $rows[] = [
                'user_id' => $aggregate['user_id'],
                'full_name' => $aggregate['full_name'],
                'role' => $aggregate['role'],
                'branch_name' => $aggregate['branch_name'],
                'days_tracked' => $aggregate['days_tracked'],
                'days_present' => $aggregate['days_present'],
                'days_half_day' => $aggregate['days_half_day'],
                'days_late' => $aggregate['days_late'],
                'days_absent' => $aggregate['days_absent'],
            ];
        }

        usort($rows, static function (array $a, array $b): int {
            if ($a['days_present'] !== $b['days_present']) {
                return $b['days_present'] <=> $a['days_present'];
            }

            if ($a['days_half_day'] !== $b['days_half_day']) {
                return $b['days_half_day'] <=> $a['days_half_day'];
            }

            if ($a['days_late'] !== $b['days_late']) {
                return $a['days_late'] <=> $b['days_late'];
            }

            return strcmp($a['full_name'], $b['full_name']);
        });



        foreach ($rows as $index => &$row) {

            $row['rank'] = $index + 1;

        }

        unset($row);



        return $rows;

    }

    private function dayHasClockEvents(string $date, ?int $branchId = null): bool
    {
        if (! Schema::hasTable('staff_attendance')) {
            return false;
        }

        [$start, $end] = $this->dayBoundsUtc($date);
        $params = [$start, $end];
        $branchSql = '';

        if ($branchId !== null && $branchId > 0) {
            $branchSql = 'AND sa.branch_id = ?';
            $params[] = $branchId;
        }

        $row = DB::selectOne(
            "SELECT COUNT(*) AS total
             FROM staff_attendance sa
             WHERE sa.created_at BETWEEN ? AND ?
             {$branchSql}",
            $params,
        );

        return (int) ($row->total ?? 0) > 0;
    }

    /**
     * @return list<array<string, mixed>>
     */
    public function eventLog(string $startDate, string $endDate, ?int $branchId = null): array
    {
        if (! Schema::hasTable('staff_attendance')) {
            return [];
        }

        $start = Carbon::parse($startDate)->startOfDay()->format('Y-m-d H:i:s');
        $end = Carbon::parse($endDate)->endOfDay()->format('Y-m-d H:i:s');
        $params = [$start, $end];
        $branchSql = '';

        if ($branchId !== null && $branchId > 0) {
            $branchSql = 'AND sa.branch_id = ?';
            $params[] = $branchId;
        }

        $rows = DB::select(
            "SELECT sa.id, sa.user_id, sa.event_type, sa.created_at, sa.device_info,
                    sa.within_geofence, sa.distance_from_branch_km,
                    u.full_name, u.role, COALESCE(b.name, 'Unassigned') AS branch_name
             FROM staff_attendance sa
             INNER JOIN users u ON u.id = sa.user_id
             LEFT JOIN branches b ON b.id = sa.branch_id
             WHERE sa.created_at BETWEEN ? AND ?
             {$branchSql}
             ORDER BY sa.created_at DESC",
            $params,
        );

        return array_map(static function (object $row): array {
            return [
                'id' => (int) $row->id,
                'user_id' => (int) $row->user_id,
                'full_name' => (string) ($row->full_name ?? ''),
                'role' => (string) ($row->role ?? ''),
                'branch_name' => (string) ($row->branch_name ?? ''),
                'event_type' => (string) ($row->event_type ?? ''),
                'recorded_at' => (string) ($row->created_at ?? ''),
                'device_info' => (string) ($row->device_info ?? ''),
                'within_geofence' => $row->within_geofence === null
                    ? null
                    : (bool) $row->within_geofence,
                'distance_km' => $row->distance_from_branch_km !== null
                    ? (float) $row->distance_from_branch_km
                    : null,
            ];
        }, $rows);
    }

    /**

     * @return array<string, mixed>

     */

    public function clock(

        string $eventType,

        int $userId,

        int $branchId,

        float $latitude,

        float $longitude,

        ?float $accuracyMeters = null,

        ?string $deviceInfo = null,

        ?bool $faceVerified = null,

        bool $adminManual = false,

        ?string $photoUrl = null,

    ): array {

        if (! in_array($eventType, ['clock_in', 'clock_out'], true)) {

            throw new \InvalidArgumentException('Invalid attendance event');

        }



        $user = DB::selectOne(

            'SELECT id, full_name, branch_id, status FROM users WHERE id = ? LIMIT 1',

            [$userId],

        );

        if (! $user) {

            throw new \RuntimeException('Staff member not found');

        }

        if (PosHelpers::columnExists('users', 'status') && (int) ($user->status ?? 1) !== 1) {

            throw new \RuntimeException('Your account is inactive');

        }



        $branch = DB::selectOne(

            'SELECT id, name, latitude, longitude, geofence_radius_km, is_active

             FROM branches WHERE id = ? LIMIT 1',

            [$branchId],

        );

        if (! $branch) {

            throw new \RuntimeException('Branch not found');

        }

        if ((int) ($branch->is_active ?? 1) !== 1) {

            throw new \RuntimeException('Branch is inactive');

        }



        $today = Carbon::today()->format('Y-m-d');
        $status = $this->userStatus($userId, $today);
        $this->assertValidPunch($eventType, $status, $today);



        if ($adminManual || ! self::requiresGps()) {
            $geofence = [
                'skipped' => true,
                'within' => true,
                'distance_km' => null,
            ];
            if ($latitude === 0.0 && $longitude === 0.0
                && $branch->latitude !== null && $branch->longitude !== null) {
                $latitude = (float) $branch->latitude;
                $longitude = (float) $branch->longitude;
            }
        } else {
            $geofence = Geofence::check(
                $branch->latitude !== null ? (float) $branch->latitude : null,
                $branch->longitude !== null ? (float) $branch->longitude : null,
                (float) ($branch->geofence_radius_km ?? 2.0),
                $latitude,
                $longitude,
            );

            if (! $geofence['skipped'] && ! $geofence['within']) {
                $radius = (float) ($branch->geofence_radius_km ?? 2.0);

                throw new \RuntimeException(
                    sprintf(
                        'You are %.2f km from %s. Must be within %.1f km to clock %s.',
                        $geofence['distance_km'],
                        $branch->name,
                        $radius,
                        $eventType === 'clock_in' ? 'in' : 'out',
                    ),
                );
            }
        }



        if ($adminManual) {
            $deviceInfo = $deviceInfo ?: 'Web Admin Manual';
        }



        $payload = [
            'user_id' => $userId,
            'branch_id' => $branchId,
            'event_type' => $eventType,
            'latitude' => $latitude,
            'longitude' => $longitude,
            'accuracy_meters' => $accuracyMeters,
            'distance_from_branch_km' => $geofence['distance_km'],
            'within_geofence' => $adminManual
                ? null
                : ($geofence['skipped'] ? null : ($geofence['within'] ? 1 : 0)),
            'face_verified' => $faceVerified === null ? null : ($faceVerified ? 1 : 0),
            'device_info' => $deviceInfo,
            'created_at' => Carbon::now('UTC'),
        ];

        if ($photoUrl !== null && $photoUrl !== '' && PosHelpers::columnExists('staff_attendance', 'photo_url')) {
            $payload['photo_url'] = $photoUrl;
        }

        $recordId = PosHelpers::insertRow('staff_attendance', $payload, [
            'user_id' => $userId,
            'event_type' => $eventType,
        ]);



        PosHelpers::insertAuditLog(

            $userId,

            $eventType,

            'attendance',

            'staff_attendance',

            $recordId,

            ucfirst(str_replace('_', ' ', $eventType)).' at '.$branch->name,

            [

                'branch_id' => $branchId,

                'latitude' => $latitude,

                'longitude' => $longitude,

                'distance_km' => $geofence['distance_km'],

                'within_geofence' => $geofence['within'],

            ],

        );



        $updatedStatus = $this->userStatus($userId);



        return [

            'id' => $recordId,

            'event_type' => $eventType,

            'user_id' => $userId,

            'branch_id' => $branchId,

            'branch_name' => (string) $branch->name,

            'within_geofence' => $geofence['within'],

            'distance_km' => $geofence['distance_km'],

            'geofence_skipped' => $geofence['skipped'],

            'is_late' => $eventType === 'clock_in' ? (bool) ($updatedStatus['is_late'] ?? false) : false,

            'punctuality_status' => $eventType === 'clock_in'

                ? (string) ($updatedStatus['punctuality_status'] ?? 'not_in_yet')

                : null,

            'status' => $updatedStatus,

            'photo_url' => $photoUrl,

        ];

    }



    /**

     * @param  array<int, object>  $events

     * @return array<string, mixed>

     */

    private function summarizeDay(array $events, string $date): array

    {

        $clockIn = null;

        $clockOut = null;

        $lastLat = null;

        $lastLng = null;

        $withinGeofence = null;

        $distanceKm = null;

        $totalMinutes = 0;

        $openIn = null;

        $punchTimes = [];



        foreach ($events as $event) {

            $type = (string) $event->event_type;

            $at = (string) $event->created_at;

            $punchTimes[] = [
                'type' => $type,
                'at' => $at,
                'photo_url' => isset($event->photo_url) && $event->photo_url !== null && $event->photo_url !== ''
                    ? (string) $event->photo_url
                    : null,
            ];



            if ($type === 'clock_in') {

                if ($clockIn === null) {

                    $clockIn = $at;

                }

                $openIn = Carbon::parse($at);

            }



            if ($type === 'clock_out' && $openIn !== null) {

                $clockOut = $at;

                $totalMinutes += $openIn->diffInMinutes(Carbon::parse($at));

                $openIn = null;

            }



            if ($event->latitude !== null) {

                $lastLat = (float) $event->latitude;

            }

            if ($event->longitude !== null) {

                $lastLng = (float) $event->longitude;

            }

            if ($event->within_geofence !== null) {

                $withinGeofence = (bool) $event->within_geofence;

            }

            if ($event->distance_from_branch_km !== null) {

                $distanceKm = (float) $event->distance_from_branch_km;

            }

        }



        $isClockedIn = $openIn !== null;

        $punchState = $this->analyzePunchState($punchTimes, $date, $isClockedIn);
        $sessionAttendance = $this->evaluateSessionAttendance(
            $punchState['morning_in_at'],
            $punchState['afternoon_in_at'],
            $date,
        );



        return [

            'clock_in_at' => $this->apiTime($clockIn),

            'clock_out_at' => $isClockedIn ? null : $this->apiTime($clockOut),

            'morning_in_at' => $this->apiTime($punchState['morning_in_at']),

            'lunch_out_at' => $this->apiTime($punchState['lunch_out_at']),

            'afternoon_in_at' => $this->apiTime($punchState['afternoon_in_at']),

            'day_out_at' => $this->apiTime($punchState['day_out_at']),

            'clock_in_display' => $this->apiTimeLabel($clockIn),

            'clock_out_display' => $isClockedIn ? null : $this->apiTimeLabel($clockOut),

            'morning_in_display' => $this->apiTimeLabel($punchState['morning_in_at']),

            'lunch_out_display' => $this->apiTimeLabel($punchState['lunch_out_at']),

            'afternoon_in_display' => $this->apiTimeLabel($punchState['afternoon_in_at']),

            'day_out_display' => $this->apiTimeLabel($punchState['day_out_at']),

            'morning_in_photo_url' => $punchState['morning_in_photo_url'] ?? null,

            'lunch_out_photo_url' => $punchState['lunch_out_photo_url'] ?? null,

            'afternoon_in_photo_url' => $punchState['afternoon_in_photo_url'] ?? null,

            'day_out_photo_url' => $punchState['day_out_photo_url'] ?? null,

            'punch_count' => $punchState['punch_count'],

            'next_action' => $punchState['next_action'],

            'next_action_note' => $punchState['next_action_note'],

            'day_complete' => $punchState['day_complete'],

            'day_type' => $punchState['day_type'],

            'total_minutes' => $totalMinutes,

            'total_hours_label' => $this->formatDuration($totalMinutes),

            'is_clocked_in' => $isClockedIn,

            'last_latitude' => $lastLat,

            'last_longitude' => $lastLng,

            'within_geofence' => $withinGeofence,

            'distance_km' => $distanceKm,

            ...$sessionAttendance,

        ];

    }



    /**

     * @param  array<int, array{type: string, at: string}>  $punches

     * @return array{

     *     punch_count: int,

     *     next_action: string|null,

     *     day_complete: bool,

     *     day_type: string,

     *     morning_in_at: string|null,

     *     lunch_out_at: string|null,

     *     afternoon_in_at: string|null,

     *     day_out_at: string|null

     * }

     */

    private function analyzePunchState(array $punches, string $date, bool $isClockedIn): array

    {

        $schedule = $this->schedule();

        $count = count($punches);

        $isToday = Carbon::parse($date, self::DISPLAY_TIMEZONE)->isToday();

        $now = $this->nowLocal();



        $morningIn = null;

        $lunchOut = null;

        $afternoonIn = null;

        $dayOut = null;

        $morningInPhoto = null;

        $lunchOutPhoto = null;

        $afternoonInPhoto = null;

        $dayOutPhoto = null;



        foreach ($punches as $punch) {
            $slot = $this->classifyPunchSlot($punch['type'], $punch['at'], $date, $schedule);
            if ($slot === null) {
                continue;
            }

            $photo = isset($punch['photo_url']) && is_string($punch['photo_url']) && $punch['photo_url'] !== ''
                ? $punch['photo_url']
                : null;

            if ($slot === 'morning_in' && $morningIn === null) {
                $morningIn = $punch['at'];
                $morningInPhoto = $photo;
            } elseif ($slot === 'lunch_out' && $lunchOut === null) {
                $lunchOut = $punch['at'];
                $lunchOutPhoto = $photo;
            } elseif ($slot === 'afternoon_in' && $afternoonIn === null) {
                $afternoonIn = $punch['at'];
                $afternoonInPhoto = $photo;
            } elseif ($slot === 'day_out' && $dayOut === null) {
                $dayOut = $punch['at'];
                $dayOutPhoto = $photo;
            }
        }

        $hasFullDay = $morningIn !== null
            && $lunchOut !== null
            && $afternoonIn !== null
            && $dayOut !== null;
        $isAfternoonOnlyHalf = $morningIn === null
            && $afternoonIn !== null
            && $dayOut !== null
            && ! $isClockedIn;
        $isMorningOnlyHalf = $morningIn !== null
            && $lunchOut !== null
            && $afternoonIn === null
            && $dayOut === null
            && ! $isClockedIn;

        $dayComplete = false;

        $dayType = 'none';

        $nextActionNote = null;

        if ($hasFullDay) {
            $dayComplete = true;
            $dayType = 'full';
        } elseif ($isAfternoonOnlyHalf) {
            $dayComplete = true;
            $dayType = 'half';
        } elseif ($isMorningOnlyHalf) {
            if ($isToday) {
                $afternoonCutoff = $this->scheduleAt($date, $schedule['afternoon_cutoff']);

                if ($now->gte($afternoonCutoff)) {
                    $dayComplete = true;
                    $dayType = 'half';
                } else {
                    $dayType = 'in_progress';
                }
            } else {
                $dayComplete = true;
                $dayType = 'half';
            }
        } elseif ($count > 0) {
            $dayType = 'in_progress';
        }



        $nextAction = null;

        $nextActionNote = null;

        if ($count === 0 && $isToday && $this->isPastAllClockInWindows($date)) {

            $dayComplete = true;

            $dayType = 'none';

            $nextActionNote = 'Absent for today.';

        } elseif (! $dayComplete) {

            if ($count === 0) {

                if ($isToday) {

                    $blocked = $this->punchWindowBlockedMessage(0, 'clock_in', false, $date);

                    if ($blocked !== null) {

                        $nextAction = null;

                        $nextActionNote = $blocked;

                    } else {

                        $nextAction = 'clock_in';

                    }

                } else {

                    $nextAction = 'clock_in';

                }

            } elseif ($isClockedIn) {

                $blocked = $this->punchWindowBlockedMessage($count, 'clock_out', true, $date);

                if ($blocked !== null) {

                    $nextAction = null;

                    $nextActionNote = $blocked;

                } else {

                    $nextAction = 'clock_out';

                }

            } elseif ($count < 4) {

                $blocked = $this->punchWindowBlockedMessage($count, 'clock_in', false, $date);

                if ($blocked !== null) {

                    $nextAction = null;

                    $nextActionNote = $blocked;

                } else {

                    $nextAction = 'clock_in';

                }

            }

        }



        return [

            'punch_count' => $count,

            'next_action' => $nextAction,

            'next_action_note' => $nextActionNote,

            'day_complete' => $dayComplete,

            'day_type' => $dayType,

            'morning_in_at' => $morningIn,

            'lunch_out_at' => $lunchOut,

            'afternoon_in_at' => $afternoonIn,

            'day_out_at' => $dayOut,

            'morning_in_photo_url' => $morningInPhoto,

            'lunch_out_photo_url' => $lunchOutPhoto,

            'afternoon_in_photo_url' => $afternoonInPhoto,

            'day_out_photo_url' => $dayOutPhoto,

        ];

    }



    /**

     * @param  array<string, mixed>  $status

     */

    private function assertValidPunch(string $eventType, array $status, string $date): void

    {

        if (! empty($status['day_complete'])) {

            if (
                (int) ($status['punch_count'] ?? 0) === 0
                && ($status['punctuality_status'] ?? '') === 'absent'
            ) {

                throw new \RuntimeException(

                    'Absent for today. No attendance was recorded.',

                );

            }

            throw new \RuntimeException(

                'Attendance completed for today. You can clock in again tomorrow.',

            );

        }



        $nextAction = $status['next_action'] ?? null;

        if ($nextAction === null) {

            if (! empty($status['day_complete'])) {

                throw new \RuntimeException(

                    'Attendance completed for today. You can clock in again tomorrow.',

                );

            }

            $note = $status['next_action_note'] ?? null;

            if (is_string($note) && $note !== '') {

                throw new \RuntimeException($note);

            }

            $schedule = $this->schedule();

            $afternoonStart = $this->scheduleAt($date, $schedule['afternoon_accept_start']);

            if (
                $eventType === 'clock_in'
                && (int) ($status['punch_count'] ?? 0) === 0
                && Carbon::parse($date, self::DISPLAY_TIMEZONE)->isToday()
                && $this->nowLocal()->gte($this->scheduleAt($date, $schedule['morning_cutoff']))
                && $this->nowLocal()->lt($afternoonStart)
            ) {
                throw new \RuntimeException(sprintf(
                    'Morning absent — you missed the morning window. Afternoon in opens at %s.',
                    $this->formatClockLabel($schedule['afternoon_accept_start']),
                ));
            }

            throw new \RuntimeException(

                'Cannot punch right now. Wait for the next scheduled time.',

            );

        }



        if ($eventType !== $nextAction) {

            if ($nextAction === 'clock_out') {

                throw new \RuntimeException('You must clock out first.');

            }

            throw new \RuntimeException('You must clock in first.');

        }



        $blocked = $this->punchWindowBlockedMessage(
            (int) ($status['punch_count'] ?? 0),
            $eventType,
            (bool) ($status['is_clocked_in'] ?? false),
            $date,
        );

        if ($blocked !== null) {

            throw new \RuntimeException($blocked);

        }



        $punchCount = (int) ($status['punch_count'] ?? 0);

        if ($punchCount >= 4) {

            throw new \RuntimeException(

                'Maximum punches for today reached. Come back tomorrow.',

            );

        }

    }



    /**
     * @param  array<string, mixed>  $schedule
     */
    private function classifyPunchSlot(string $type, string $at, string $date, array $schedule): ?string
    {
        $local = Carbon::parse($at, 'UTC')->timezone(self::DISPLAY_TIMEZONE);
        $time = $local->format('H:i');

        if ($type === 'clock_in') {
            $morningAcceptStart = $schedule['morning_accept_start'];
            $morningCutoff = $schedule['morning_cutoff'];
            $afternoonAcceptStart = $schedule['afternoon_accept_start'];
            $afternoonCutoff = $schedule['afternoon_cutoff'];

            if ($time < $morningAcceptStart || ($time >= $morningAcceptStart && $time < $morningCutoff)) {
                return 'morning_in';
            }

            if ($time >= $afternoonAcceptStart && $time < $afternoonCutoff) {
                return 'afternoon_in';
            }

            return null;
        }

        if ($type === 'clock_out') {
            $breakOutStart = $schedule['break_out_start'];
            $breakOutEnd = $schedule['break_out_end'];
            $timeoutStart = $schedule['timeout_start'];

            if ($time >= $breakOutStart && $time <= $breakOutEnd) {
                return 'lunch_out';
            }

            if ($time >= $timeoutStart) {
                return 'day_out';
            }

            return null;
        }

        return null;
    }

    private function nowLocal(): Carbon
    {
        return Carbon::now(self::DISPLAY_TIMEZONE);
    }

    private function scheduleAt(string $date, string $time): Carbon
    {
        return Carbon::parse($date.' '.$time, self::DISPLAY_TIMEZONE);
    }

    private function punchWindowBlockedMessage(
        int $punchCount,
        string $eventType,
        bool $isClockedIn,
        string $date,
    ): ?string {
        if (! Carbon::parse($date, self::DISPLAY_TIMEZONE)->isToday()) {
            return null;
        }

        $schedule = $this->schedule();
        $now = $this->nowLocal();

        $morningAcceptStart = $this->scheduleAt($date, $schedule['morning_accept_start']);
        $morningCutoff = $this->scheduleAt($date, $schedule['morning_cutoff']);
        $breakOutStart = $this->scheduleAt($date, $schedule['break_out_start']);
        $breakOutEnd = $this->scheduleAt($date, $schedule['break_out_end']);
        $afternoonAcceptStart = $this->scheduleAt($date, $schedule['afternoon_accept_start']);
        $afternoonCutoff = $this->scheduleAt($date, $schedule['afternoon_cutoff']);
        $timeoutStart = $this->scheduleAt($date, $schedule['timeout_start']);

        if ($eventType === 'clock_in' && $punchCount === 0) {
            if ($now->lt($morningAcceptStart)) {
                return sprintf(
                    'Too early for morning in. Opens at %s.',
                    $this->formatClockLabel($schedule['morning_accept_start']),
                );
            }

            if ($now->lt($morningCutoff)) {
                return null;
            }

            if ($now->lt($afternoonAcceptStart)) {
                return sprintf(
                    'Morning window closed (%s–%s). Afternoon in opens at %s.',
                    $this->formatClockLabel($schedule['morning_accept_start']),
                    $this->formatClockLabel($schedule['morning_cutoff']),
                    $this->formatClockLabel($schedule['afternoon_accept_start']),
                );
            }

            if ($now->gt($afternoonCutoff)) {
                return 'Absent for today. All clock-in windows have closed.';
            }

            return null;
        }

        if ($eventType === 'clock_out' && $punchCount === 1 && $isClockedIn) {
            if ($now->lt($breakOutStart)) {
                return sprintf(
                    'Too early for lunch out. Opens at %s.',
                    $this->formatClockLabel($schedule['break_out_start']),
                );
            }

            if ($now->gt($breakOutEnd)) {
                return sprintf(
                    'Lunch out window closed (%s–%s).',
                    $this->formatClockLabel($schedule['break_out_start']),
                    $this->formatClockLabel($schedule['break_out_end']),
                );
            }

            return null;
        }

        if ($eventType === 'clock_in' && $punchCount === 2 && ! $isClockedIn) {
            if ($now->lt($afternoonAcceptStart)) {
                return sprintf(
                    'Too early for afternoon in. Opens at %s.',
                    $this->formatClockLabel($schedule['afternoon_accept_start']),
                );
            }

            if ($now->gt($afternoonCutoff)) {
                return 'Missed afternoon in window for today.';
            }

            return null;
        }

        if ($eventType === 'clock_out' && $punchCount === 3 && $isClockedIn) {
            if ($now->lt($timeoutStart)) {
                return sprintf(
                    'Too early for end-of-day out. Day out opens at %s.',
                    $this->formatClockLabel($schedule['timeout_start']),
                );
            }

            return null;
        }

        return null;
    }

    private function isPastAllClockInWindows(string $date): bool
    {
        if (! Carbon::parse($date, self::DISPLAY_TIMEZONE)->isToday()) {
            return false;
        }

        $schedule = $this->schedule();
        $afternoonCutoff = $this->scheduleAt($date, $schedule['afternoon_cutoff']);

        return $this->nowLocal()->gte($afternoonCutoff);
    }

    private function formatClockLabel(string $time): string

    {

        $parsed = Carbon::createFromFormat('H:i', $time);



        return $parsed->format('g:i A');

    }



    /**
     * @return array{
     *     morning_session_status: string,
     *     afternoon_session_status: string,
     *     daily_status: string,
     *     punctuality_status: string,
     *     is_late: bool,
     *     minutes_from_start: int|null,
     *     minutes_late: int,
     *     expected_start_time: string,
     *     late_after_time: string,
     *     morning_absent_after_time: string,
     *     is_morning_absent: bool
     * }
     */
    private function evaluateSessionAttendance(?string $morningInAt, ?string $afternoonInAt, string $date): array
    {
        $schedule = $this->schedule();
        $isToday = Carbon::parse($date, self::DISPLAY_TIMEZONE)->isToday();
        $now = $this->nowLocal();

        $morningOfficial = $this->scheduleAt($date, $schedule['morning_official_start']);
        $morningGraceEnd = $this->scheduleAt($date, $schedule['morning_grace_end']);
        $morningLateStart = $this->scheduleAt($date, $schedule['morning_late_start']);
        $morningCutoff = $this->scheduleAt($date, $schedule['morning_cutoff']);

        $afternoonAcceptStart = $this->scheduleAt($date, $schedule['afternoon_accept_start']);
        $afternoonOnTimeEnd = $this->scheduleAt($date, $schedule['afternoon_on_time_end']);
        $afternoonLateStart = $this->scheduleAt($date, $schedule['afternoon_late_start']);
        $afternoonCutoff = $this->scheduleAt($date, $schedule['afternoon_cutoff']);

        $morningStatus = $this->resolveMorningSessionStatus(
            $morningInAt,
            $isToday,
            $now,
            $morningOfficial,
            $morningGraceEnd,
            $morningLateStart,
            $morningCutoff,
        );

        $afternoonStatus = $this->resolveAfternoonSessionStatus(
            $afternoonInAt,
            $isToday,
            $now,
            $afternoonAcceptStart,
            $afternoonOnTimeEnd,
            $afternoonLateStart,
            $afternoonCutoff,
        );

        $dailyStatus = $this->resolveDailyStatus($morningStatus, $afternoonStatus);

        $minutesFromStart = null;
        $minutesLate = 0;
        $isLate = false;

        if ($morningInAt !== null) {
            $morningIn = Carbon::parse($morningInAt, 'UTC')->timezone(self::DISPLAY_TIMEZONE);
            $minutesFromStart = (int) $morningOfficial->diffInMinutes($morningIn, false);

            if ($morningStatus === 'late') {
                $isLate = true;
                $minutesLate = (int) $morningLateStart->diffInMinutes($morningIn);
            }
        }

        $punctualityStatus = $morningStatus;
        if ($dailyStatus === 'absent' && $morningStatus === 'not_in_yet') {
            $punctualityStatus = 'absent';
        }

        return [
            'morning_session_status' => $morningStatus,
            'afternoon_session_status' => $afternoonStatus,
            'daily_status' => $dailyStatus,
            'punctuality_status' => $punctualityStatus,
            'is_morning_absent' => $morningStatus === 'absent',
            'is_late' => $isLate,
            'minutes_from_start' => $minutesFromStart,
            'minutes_late' => $minutesLate,
            'expected_start_time' => $schedule['morning_official_start'],
            'late_after_time' => $schedule['morning_late_start'],
            'morning_absent_after_time' => $schedule['morning_cutoff'],
        ];
    }

    private function resolveMorningSessionStatus(
        ?string $morningInAt,
        bool $isToday,
        Carbon $now,
        Carbon $officialStart,
        Carbon $graceEnd,
        Carbon $lateStart,
        Carbon $cutoff,
    ): string {
        if ($morningInAt !== null) {
            $clockIn = Carbon::parse($morningInAt, 'UTC')->timezone(self::DISPLAY_TIMEZONE);

            if ($clockIn->gte($cutoff)) {
                return 'absent';
            }

            if ($clockIn->gte($lateStart)) {
                return 'late';
            }

            return 'present';
        }

        if (! $isToday) {
            return 'absent';
        }

        if ($now->gte($cutoff)) {
            return 'absent';
        }

        return 'not_in_yet';
    }

    private function resolveAfternoonSessionStatus(
        ?string $afternoonInAt,
        bool $isToday,
        Carbon $now,
        Carbon $acceptStart,
        Carbon $onTimeEnd,
        Carbon $lateStart,
        Carbon $cutoff,
    ): string {
        if ($afternoonInAt !== null) {
            $clockIn = Carbon::parse($afternoonInAt, 'UTC')->timezone(self::DISPLAY_TIMEZONE);

            if ($clockIn->gte($cutoff)) {
                return 'absent';
            }

            if ($clockIn->gte($lateStart)) {
                return 'late';
            }

            return 'present';
        }

        if (! $isToday) {
            return 'absent';
        }

        if ($now->gte($cutoff)) {
            return 'absent';
        }

        return 'not_in_yet';
    }

    private function resolveDailyStatus(string $morningStatus, string $afternoonStatus): string
    {
        if ($morningStatus === 'absent' && $afternoonStatus === 'absent') {
            return 'absent';
        }

        if ($morningStatus === 'absent' || $afternoonStatus === 'absent') {
            return 'half_day';
        }

        if (
            in_array($morningStatus, ['present', 'late'], true)
            && in_array($afternoonStatus, ['present', 'late'], true)
        ) {
            return 'present';
        }

        return 'in_progress';
    }



    private function normalizeTime(string $time): string

    {

        $time = trim($time);

        if (preg_match('/^(\d{1,2}):(\d{2})$/', $time, $matches) !== 1) {

            return '08:00';

        }



        $hour = max(0, min(23, (int) $matches[1]));

        $minute = max(0, min(59, (int) $matches[2]));



        return sprintf('%02d:%02d', $hour, $minute);

    }



    private const DISPLAY_TIMEZONE = 'Asia/Manila';

    /**
     * @return array{0: string, 1: string}
     */
    private function dayBoundsUtc(string $date): array
    {
        $start = Carbon::parse($date, self::DISPLAY_TIMEZONE)->startOfDay()->utc();
        $end = Carbon::parse($date, self::DISPLAY_TIMEZONE)->endOfDay()->utc();

        return [$start->format('Y-m-d H:i:s'), $end->format('Y-m-d H:i:s')];
    }

    private function apiTime(?string $at): ?string
    {
        if ($at === null || trim($at) === '') {
            return null;
        }

        return Carbon::parse($at, 'UTC')
            ->timezone(self::DISPLAY_TIMEZONE)
            ->toIso8601String();
    }

    private function apiTimeLabel(?string $at): ?string
    {
        if ($at === null || trim($at) === '') {
            return null;
        }

        return Carbon::parse($at, 'UTC')
            ->timezone(self::DISPLAY_TIMEZONE)
            ->format('g:i A');
    }

    private function formatDuration(int $minutes): string

    {

        $hours = intdiv($minutes, 60);

        $mins = $minutes % 60;



        return "{$hours} hrs {$mins} mins";

    }

}


