-- CreateEnum
CREATE TYPE "GatewayType" AS ENUM ('MESH', 'VOIP', 'GSM', 'JASMIN', 'JAMBONZ');

-- CreateEnum
CREATE TYPE "CdrDirection" AS ENUM ('INBOUND', 'OUTBOUND');

-- CreateEnum
CREATE TYPE "CdrStatus" AS ENUM ('QUEUED', 'RINGING', 'IN_PROGRESS', 'COMPLETED', 'FAILED', 'BUSY', 'NO_ANSWER', 'CANCELED');

-- CreateTable
CREATE TABLE "api_keys" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "key_prefix" TEXT NOT NULL,
    "key_hash" TEXT NOT NULL,
    "revoked_at" TIMESTAMP(3),
    "last_used_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "api_keys_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "cdrs" (
    "id" UUID NOT NULL,
    "call_sid" TEXT NOT NULL,
    "client_ref" TEXT,
    "direction" "CdrDirection" NOT NULL,
    "from_number" TEXT NOT NULL,
    "to_number" TEXT NOT NULL,
    "gateway_type" "GatewayType" NOT NULL,
    "status" "CdrStatus" NOT NULL,
    "consent_flag" BOOLEAN NOT NULL DEFAULT false,
    "duration_sec" INTEGER NOT NULL DEFAULT 0,
    "cost_micros" INTEGER NOT NULL DEFAULT 0,
    "mesh_hops" INTEGER,
    "bitrate" INTEGER,
    "jitter_ms" INTEGER,
    "packet_loss_pct" DOUBLE PRECISION,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "cdrs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "api_keys_key_hash_key" ON "api_keys"("key_hash");

-- CreateIndex
CREATE INDEX "api_keys_key_prefix_idx" ON "api_keys"("key_prefix");

-- CreateIndex
CREATE UNIQUE INDEX "cdrs_call_sid_key" ON "cdrs"("call_sid");

-- CreateIndex
CREATE INDEX "cdrs_from_number_idx" ON "cdrs"("from_number");

-- CreateIndex
CREATE INDEX "cdrs_to_number_idx" ON "cdrs"("to_number");

-- CreateIndex
CREATE INDEX "cdrs_gateway_type_status_idx" ON "cdrs"("gateway_type", "status");

-- CreateIndex
CREATE INDEX "cdrs_created_at_idx" ON "cdrs"("created_at");
