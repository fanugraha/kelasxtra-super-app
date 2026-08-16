#!/usr/bin/env bash
# apply_db_sync_scripts_16aug2026.sh
#
# Menambahkan 2 npm script baru untuk mencegah masalah berulang: migration
# yang sukses di database dev (.env) tapi kelupaan di-apply ke database
# test (.env.test), baru ketahuan pas npm run test:e2e gagal.
#
#   npm run db:sync-test    -- deploy migration pending ke database test saja
#                               (dibaca dari .env.test)
#   npm run db:migrate -- --name nama_migration
#                            -- pengganti "npx prisma migrate dev --name ...":
#                               jalan seperti biasa ke database dev, LALU
#                               otomatis lanjut sync ke database test juga.
#
# Idempotent -- aman dijalankan berkali-kali.
# Jalankan dari ROOT folder project backend (kelasxtra-super-app).

set -e

if [ ! -f "package.json" ] || [ ! -d "prisma" ]; then
  echo "Jalankan script ini dari root folder backend (kelasxtra-super-app), bukan dari folder lain."
  exit 1
fi

mkdir -p scripts

echo ">> Menulis package.json"
mkdir -p $(dirname package.json)
cat > package.json << 'FILEEOF'
{
  "name": "backend",
  "version": "0.0.1",
  "description": "",
  "author": "",
  "private": true,
  "license": "UNLICENSED",
  "scripts": {
    "build": "nest build",
    "format": "prettier --write \"src/**/*.ts\" \"test/**/*.ts\"",
    "start": "nest start",
    "start:dev": "nest start --watch",
    "start:debug": "nest start --debug --watch",
    "start:prod": "node dist/main",
    "lint": "eslint \"{src,apps,libs,test}/**/*.ts\" --fix",
    "test": "jest",
    "test:watch": "jest --watch",
    "test:cov": "jest --coverage",
    "test:debug": "node --inspect-brk -r tsconfig-paths/register -r ts-node/register node_modules/.bin/jest --runInBand",
    "test:e2e": "cross-env NODE_OPTIONS=--experimental-vm-modules jest --config ./test/jest-e2e.json",
    "db:sync-test": "bash scripts/sync-test-db.sh",
    "db:migrate": "bash scripts/migrate-dev-and-sync.sh"
  },
  "dependencies": {
    "@nestjs/common": "^11.0.1",
    "@nestjs/core": "^11.0.1",
    "@nestjs/jwt": "^11.0.2",
    "@nestjs/passport": "^11.0.5",
    "@nestjs/platform-express": "^11.0.1",
    "@nestjs/schedule": "^6.1.3",
    "@nestjs/throttler": "^6.5.0",
    "@prisma/adapter-mariadb": "^7.9.1",
    "@prisma/client": "^7.9.1",
    "bcrypt": "^6.0.0",
    "class-transformer": "^0.5.1",
    "class-validator": "^0.15.1",
    "dotenv": "^17.4.2",
    "helmet": "^8.3.0",
    "passport": "^0.7.0",
    "passport-jwt": "^4.0.1",
    "reflect-metadata": "^0.2.2",
    "rxjs": "^7.8.1"
  },
  "devDependencies": {
    "@eslint/eslintrc": "^3.2.0",
    "@eslint/js": "^9.18.0",
    "@nestjs/cli": "^11.0.0",
    "@nestjs/schematics": "^11.0.0",
    "@nestjs/testing": "^11.0.1",
    "@types/bcrypt": "^6.0.0",
    "@types/express": "^5.0.0",
    "@types/jest": "^30.0.0",
    "@types/node": "^24.0.0",
    "@types/passport-jwt": "^4.0.1",
    "@types/supertest": "^7.0.0",
    "cross-env": "^10.1.0",
    "eslint": "^9.18.0",
    "eslint-config-prettier": "^10.0.1",
    "eslint-plugin-prettier": "^5.2.2",
    "globals": "^17.0.0",
    "jest": "^30.0.0",
    "prettier": "^3.4.2",
    "prisma": "^7.9.1",
    "source-map-support": "^0.5.21",
    "supertest": "^7.0.0",
    "ts-jest": "^29.2.5",
    "ts-loader": "^9.5.2",
    "ts-node": "^10.9.2",
    "tsconfig-paths": "^4.2.0",
    "tsx": "^4.23.12",
    "typescript": "^5.7.3",
    "typescript-eslint": "^8.20.0"
  },
  "jest": {
    "moduleFileExtensions": [
      "js",
      "json",
      "ts"
    ],
    "rootDir": "src",
    "testRegex": ".*\\.spec\\.ts$",
    "transform": {
      "^.+\\.(t|j)s$": "ts-jest"
    },
    "collectCoverageFrom": [
      "**/*.(t|j)s"
    ],
    "coverageDirectory": "../coverage",
    "testEnvironment": "node",
    "moduleNameMapper": {
      "^(\\.{1,2}/.*)\\.js$": "$1"
    },
    "setupFiles": [
      "dotenv/config"
    ]
  }
}
FILEEOF

echo ">> Menulis scripts/sync-test-db.sh"
mkdir -p $(dirname scripts/sync-test-db.sh)
cat > scripts/sync-test-db.sh << 'FILEEOF'
#!/usr/bin/env bash
# scripts/sync-test-db.sh
#
# Masalah berulang yang mau dicegah script ini: migration baru dibuat lewat
# `npx prisma migrate dev` (jalan otomatis ke database di .env, yaitu
# `education_app`), tapi database TEST (education_app_test, dipakai
# `npm run test:e2e`) punya .env.test SENDIRI dengan DATABASE_URL berbeda --
# jadi migration baru itu TIDAK otomatis ikut ter-apply ke sana. Baru
# ketahuan belakangan saat test:e2e tiba-tiba gagal dengan
# "column ... does not exist", padahal migration-nya sudah lama sukses di
# database dev.
#
# Script ini men-deploy migration yang PENDING (bukan bikin migration baru)
# ke database test, dengan DATABASE_URL dibaca dari .env.test -- supaya
# tidak perlu ingat-ingat command panjang tiap kali habis `migrate dev`.

set -e

if [ ! -f ".env.test" ]; then
  echo "File .env.test tidak ditemukan di folder ini. Jalankan dari root folder backend."
  exit 1
fi

TEST_DATABASE_URL=$(grep '^DATABASE_URL=' .env.test | cut -d '=' -f2- | tr -d '"')

if [ -z "$TEST_DATABASE_URL" ]; then
  echo "DATABASE_URL tidak ketemu di .env.test."
  exit 1
fi

echo ">> Sinkronkan migration ke database test ($TEST_DATABASE_URL)..."
DATABASE_URL="$TEST_DATABASE_URL" npx prisma migrate deploy

echo ""
echo ">> Selesai. Database test sudah sinkron dengan migration terbaru."
echo ">> Prisma Client tidak perlu di-generate ulang khusus untuk ini --"
echo "   generate bersifat sekali jalan berdasar schema, bukan per-database."
FILEEOF

echo ">> Menulis scripts/migrate-dev-and-sync.sh"
mkdir -p $(dirname scripts/migrate-dev-and-sync.sh)
cat > scripts/migrate-dev-and-sync.sh << 'FILEEOF'
#!/usr/bin/env bash
# scripts/migrate-dev-and-sync.sh
#
# Pengganti kebiasaan lama:
#   npx prisma migrate dev --name xxx     (ke database dev, di .env)
#   ...lupa sync ke database test...      (baru ketahuan pas test:e2e gagal)
#
# Sekarang cukup:
#   npm run db:migrate -- --name xxx
#
# Ini menjalankan `migrate dev` seperti biasa (interaktif, ke database di
# .env), LALU otomatis lanjut sync ke database test. Kalau migrate dev-nya
# dibatalkan/gagal, sync ke test TIDAK dijalankan (set -e).

set -e

echo ">> Menjalankan migrate dev ke database dev (.env)..."
npx prisma migrate dev "$@"

echo ""
echo ">> Migrate dev selesai. Lanjut sync migration ke database test..."
bash "$(dirname "$0")/sync-test-db.sh"
FILEEOF


chmod +x scripts/sync-test-db.sh scripts/migrate-dev-and-sync.sh

echo ""
echo ">> Semua file berhasil ditulis dan dibuat executable."
echo ""
echo "Mulai sekarang, tiap kali bikin migration baru, pakai ini (bukan npx prisma migrate dev langsung):"
echo "  npm run db:migrate -- --name nama_migration_kamu"
echo ""
echo "Kalau cuma mau sync migration yang SUDAH ada ke database test (kasus seperti hari ini):"
echo "  npm run db:sync-test"
