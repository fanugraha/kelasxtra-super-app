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
