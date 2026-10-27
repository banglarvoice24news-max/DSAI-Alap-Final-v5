// Jest global setup: seed the env values the config validator requires so any
// module that imports src/config/env.js (logger, redis, services) can load in a
// test worker without a real .env file. Individual tests override via jest.mock.

process.env.NODE_ENV = "test";
process.env.DATABASE_URL = "postgresql://test:test@127.0.0.1:5432/test?schema=public";
process.env.REDIS_URL = "redis://127.0.0.1:6379";
process.env.JWT_ACCESS_SECRET = "test-access-secret-min-32-chars-long";
process.env.JWT_REFRESH_SECRET = "test-refresh-secret-min-32-chars-long";
process.env.BACKUP_KEY_PEPPER = "test-backup-pepper-16+";
process.env.LOG_LEVEL = "silent";
process.env.ENABLE_CPAAS_LAYER = "false";
