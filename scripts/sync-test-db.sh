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
