# Agriculture POS — Laravel API Backend

API-only Laravel backend for the **Flutter tablet POS** and **React web admin**. JSON API lives under `/pos_app/*`; the browser UI uses Inertia + React on `/`, `/dashboard`, and `/pos`.

## Quick start

```bash
cd poslaravelbackend
composer install
copy .env.example .env   # Windows
php artisan key:generate
php artisan migrate:fresh --seed
php artisan serve --host=0.0.0.0 --port=8000
```

Default login (all seeded users): **`password`**

| Email | Role |
|-------|------|
| admin@agriculture.local | admin |
| superadmin@agriculture.local | super_admin |
| manager@agriculture.local | manager |
| cashier@agriculture.local | cashier |

## Monitor requests (Telescope)

Telescope is enabled for local development. Open:

**http://10.179.102.85:8000/telescope**

It logs all `/pos_app/*` API requests and responses when `APP_ENV=local`.

```bash
php artisan vendor:publish --tag=telescope-migrations --force
php artisan migrate
```

## Database

Migrations live in `database/migrations/2026_06_06_*` and create the full POS schema:

- users, categories, products, customers, branches
- orders, order_items
- refunds, refund_items
- loyalty_cards, app_settings, audit_logs, user_transactions
- coupons, staff_payments

Seed data: `database/seeders/PosDatabaseSeeder.php`

```bash
php artisan migrate:fresh --seed
```

Configure MySQL in `.env`:

```env
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=agri_pos
DB_USERNAME=root
DB_PASSWORD=
```

## API endpoints

Base URL: `http://YOUR_HOST:8000/pos_app`

| Endpoint | Status |
|----------|--------|
| `GET /pos_app/health` | Ready |
| `POST /pos_app/login.php` | Ready |
| `GET/POST /pos_app/categories.php` | Ready |
| `GET /pos_app/items.php` | Ready |
| Other `*.php` routes | Stub (501) — migrate next |

Same JSON format as legacy `backend/pos_app/`: `{ "success": true/false, ... }`

## Flutter tablet app

Point the tablet app at Laravel:

```bash
flutter run --dart-define=API_BASE_URL=https://YOUR_HOST/pos_app
```

Or edit `lib/config/api_config.dart`.

## React web app (Inertia)

The browser admin/POS web UI is re-enabled alongside the JSON API.

### Local development

```bash
cd poslaravelbackend
composer install
npm install
php artisan migrate --force
php artisan db:seed --force
composer dev
```

Open **http://127.0.0.1:8000** and sign in with:

| Email | Password |
|-------|----------|
| admin@agriculture.local | password |

### Production build (Hostinger)

```bash
npm ci
npm run build
php artisan config:clear
php artisan route:clear
php artisan view:clear
```

The web app and tablet app both use **`/pos_app`** for business data. Web login uses Laravel session auth; the tablet uses `POST /pos_app/login.php`.

### Web routes

| Route | Purpose |
|-------|---------|
| `/` | Welcome |
| `/login` | Web sign-in |
| `/dashboard` | Admin dashboard |
| `/pos` | POS web console (API health + future modules) |
| `/pos_app/*` | JSON API for Flutter + web fetches |

## Hostinger deployment

1. Upload `poslaravelbackend` and set the domain **document root** to `poslaravelbackend/public`.
2. In hPanel → **Databases → MySQL**, create a database and user. Copy all four values.
3. Edit `.env` on the server (not `.env.example`):

```env
APP_ENV=production
APP_DEBUG=false
APP_URL=https://posmunoz.store
APP_TIMEZONE=Asia/Manila
DB_TIMEZONE=+00:00

DB_HOST=127.0.0.1
DB_DATABASE=u123456789_agri_pos
DB_USERNAME=u123456789_posuser
DB_PASSWORD=your_strong_password

SESSION_DRIVER=file
CACHE_STORE=file
QUEUE_CONNECTION=sync
TELESCOPE_ENABLED=false
```

4. SSH or Hostinger terminal:

```bash
cd public_html/poslaravelbackend   # your path
composer install --no-dev --optimize-autoloader
npm ci
composer run deploy                # builds React assets + removes public/hot
php artisan key:generate
php artisan migrate --force
php artisan db:seed --force
php artisan pos:prepare-checkout --test-order
```

**Tablet checkout fails with “check the server database setup”:** run migrations on the server, then:

```bash
php artisan migrate --force
php artisan pos:prepare-checkout --test-order
```

The `pos:prepare-checkout` command fixes missing order columns, refreshes stock, and saves one demo walk-in sale (`INV-...`) you can verify in Reports.

**If the login page is blank and the browser console shows CORS errors to `http://127.0.0.1:5173`:**

1. Delete `public/hot` on the server (this file tells Laravel to use the Vite dev server).
2. Run `npm run build` so `public/build/manifest.json` exists.
3. In production `.env`, set `APP_ENV=production` and **do not** set `VITE_DEV_SERVER_URL`.
4. Run `php artisan config:clear` and `php artisan view:clear`.

Upload `public/build/` when deploying via FTP — it is not in git.

5. Verify:

- `https://posmunoz.store/` — JSON welcome (no DB error)
- `https://posmunoz.store/pos_app/health` — must show `"database_connected": true`

If `/pos_app/health` shows `"database_connected": false`, the `.env` DB credentials are still wrong or migrations were not run.

**Why `/` failed but `/pos_app/health` looked fine:** the old health check only printed the configured database name and never connected. Login and POS APIs require a working MySQL connection.

- React / Inertia / Vite frontend routes
- Fortify web auth UI
- Telescope debug UI
- Laravel starter `users` table (replaced with POS `users` schema)

The `resources/js` folder may still exist from the installer but is **not used**. You can delete it later if you want a cleaner tree.

## Legacy PHP

`backend/pos_app/` remains the reference implementation until each endpoint is ported to Laravel controllers in `app/Http/Controllers/Api/Pos/`.
