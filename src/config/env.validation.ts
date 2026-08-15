/**
 * Validasi environment variable wajib saat startup, sebelum NestFactory.create
 * dipanggil. JWT_ACCESS_SECRET sudah divalidasi lewat JwtStrategy constructor,
 * tapi itu hanya jalan kalau AuthModule benar-benar di-instantiate — variabel
 * lain (seperti JWT_REFRESH_SECRET, yang cuma dibaca langsung dari
 * process.env di AuthService, tanpa lewat constructor manapun) tidak pernah
 * tervalidasi sampai endpoint pertama dipanggil. Fungsi ini memastikan
 * semua secret wajib sudah ada SEBELUM app mulai menerima request sama sekali.
 */
const REQUIRED_ENV_VARS = ['JWT_ACCESS_SECRET', 'JWT_REFRESH_SECRET', 'DATABASE_URL'] as const;

export function validateRequiredEnvVars(): void {
  const missing = REQUIRED_ENV_VARS.filter((key) => !process.env[key]);

  if (missing.length > 0) {
    console.error(
      `Gagal start aplikasi: environment variable berikut belum di-set: ${missing.join(', ')}. ` +
        'Cek file .env (lihat .env.example).',
    );
    process.exit(1);
  }
}
