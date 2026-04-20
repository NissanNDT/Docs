-- PostgreSQL Schema for Nissan Body Shop Management System

-- Tabla de Roles
CREATE TABLE "Role" (
  id SERIAL PRIMARY KEY,
  name VARCHAR(50) NOT NULL UNIQUE
);

INSERT INTO "Role" (id, name) VALUES (1, 'WWS'), (2, 'SCM'), (3, 'BODY'), (4, 'CARRIER'), (5, 'ADMIN'), (6, 'WTY'), (7, 'SCM_QUALITY');

-- Reset sequence to avoid conflicts
SELECT setval('"Role_id_seq"', 7, true);

-- Tabla de Proveedores
CREATE TABLE "Provider" (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL UNIQUE,
  code VARCHAR(50),
  "createdAt" TIMESTAMP DEFAULT (NOW() AT TIME ZONE 'UTC'),
  "updatedAt" TIMESTAMP DEFAULT (NOW() AT TIME ZONE 'UTC')
);

-- Tabla de Usuarios
CREATE TABLE "User" (
  id SERIAL PRIMARY KEY,
  email VARCHAR(255) NOT NULL UNIQUE,
  password VARCHAR(255) NOT NULL,
  name VARCHAR(255) NOT NULL,
  "roleId" INT NOT NULL,
  "providerId" INT,
  plant VARCHAR(2) CHECK (plant IN ('A1', 'A2', NULL)),
  "createdAt" TIMESTAMP DEFAULT (NOW() AT TIME ZONE 'UTC'),
  "updatedAt" TIMESTAMP DEFAULT (NOW() AT TIME ZONE 'UTC'),
  CONSTRAINT "FK_User_Role" FOREIGN KEY ("roleId") REFERENCES "Role"(id),
  CONSTRAINT "FK_User_Provider" FOREIGN KEY ("providerId") REFERENCES "Provider"(id)
);

CREATE INDEX "IX_User_Email" ON "User"(email);
CREATE INDEX "IX_User_RoleId" ON "User"("roleId");
CREATE INDEX "IX_User_Plant" ON "User"(plant);

-- Tabla de Tokens de Refresco (Refresh Tokens)
CREATE TABLE "RefreshToken" (
  id SERIAL PRIMARY KEY,
  "userId" INT NOT NULL,
  token VARCHAR(500) NOT NULL UNIQUE,
  "expiresAt" TIMESTAMP NOT NULL,
  "revokedAt" TIMESTAMP,
  "createdAt" TIMESTAMP DEFAULT (NOW() AT TIME ZONE 'UTC'),
  CONSTRAINT "FK_RefreshToken_User" FOREIGN KEY ("userId") REFERENCES "User"(id) ON DELETE CASCADE
);

CREATE INDEX "IX_RefreshToken_Token" ON "RefreshToken"(token);
CREATE INDEX "IX_RefreshToken_UserId" ON "RefreshToken"("userId");
CREATE INDEX "IX_RefreshToken_ExpiresAt" ON "RefreshToken"("expiresAt");

COMMENT ON TABLE "RefreshToken" IS 'Tokens JWT de refresco para mantener sesiones de usuario';
COMMENT ON COLUMN "RefreshToken"."revokedAt" IS 'Fecha cuando el token fue revocado manualmente (logout)';
COMMENT ON COLUMN "RefreshToken"."expiresAt" IS 'Fecha de expiración natural del token';

-- Limpieza automática de refresh tokens inválidos
-- Nota: este trigger se ejecuta en eventos INSERT/UPDATE de la tabla.
-- Los tokens vencidos se eliminan en el siguiente evento de escritura.
CREATE OR REPLACE FUNCTION cleanup_invalid_refresh_tokens()
RETURNS TRIGGER AS $$
BEGIN
  DELETE FROM "RefreshToken"
  WHERE "expiresAt" <= (NOW() AT TIME ZONE 'UTC')
     OR "revokedAt" IS NOT NULL;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS "TRG_RefreshToken_AutoCleanup" ON "RefreshToken";

CREATE TRIGGER "TRG_RefreshToken_AutoCleanup"
AFTER INSERT OR UPDATE ON "RefreshToken"
FOR EACH STATEMENT
EXECUTE FUNCTION cleanup_invalid_refresh_tokens();

COMMENT ON FUNCTION cleanup_invalid_refresh_tokens() IS 'Elimina refresh tokens vencidos o revocados al escribir en RefreshToken';
COMMENT ON TRIGGER "TRG_RefreshToken_AutoCleanup" ON "RefreshToken" IS 'Limpieza automática de refresh tokens vencidos/revocados';

-- Tabla de Estados de Unidad
CREATE TABLE "UnitStatus" (
  id SERIAL PRIMARY KEY,
  name VARCHAR(50) NOT NULL UNIQUE
);

INSERT INTO "UnitStatus" (name) VALUES ('REPORTED'), ('SENT'), ('DELIVERED'), ('RECEIVED'), ('IN_REPAIR'), ('RELEASED'), ('WTY_PENDING'), ('WTY_RELEASED'), ('WWS_RELEASED'), ('ACCEPTED'), ('REJECTED'), ('UNAVAILABLE'), ('ARCHIVED');

-- Tabla de Grados de Defecto
CREATE TABLE "DefectGrade" (
  id SERIAL PRIMARY KEY,
  code VARCHAR(10) NOT NULL UNIQUE,
  description VARCHAR(100)
);

INSERT INTO "DefectGrade" (code, description) VALUES 
  ('V1', 'Defecto grave - Reparación extensa'),
  ('V2', 'Defecto moderado - Reparación media'),
  ('V3', 'Defecto leve - Reparación rápida');

-- Tabla de Modelos de Unidad (administrado por SCM)
CREATE TABLE "UnitModel" (
  id SERIAL PRIMARY KEY,
  code VARCHAR(50) NOT NULL,
  name VARCHAR(120) NOT NULL,
  "isActive" BOOLEAN DEFAULT TRUE,
  "createdAt" TIMESTAMP DEFAULT (NOW() AT TIME ZONE 'UTC'),
  "updatedAt" TIMESTAMP DEFAULT (NOW() AT TIME ZONE 'UTC'),
  CONSTRAINT "UQ_UnitModel_Code" UNIQUE (code)
);

CREATE INDEX "IX_UnitModel_IsActive" ON "UnitModel"("isActive");

-- Tabla de Unidades
CREATE TABLE "Unit" (
  id SERIAL PRIMARY KEY,
  vin VARCHAR(50) NOT NULL,
  market VARCHAR(100) NOT NULL,
  lane VARCHAR(50) NOT NULL,
  "statusId" INT NOT NULL DEFAULT 1,
  "providerId" INT,
  plant VARCHAR(2) CHECK (plant IN ('A1', 'A2', NULL)),
  "isAvailableToday" BOOLEAN DEFAULT TRUE,
  "registeredById" INT NOT NULL,
  "estimatedRepairHours" DECIMAL(5,2),
  "estimatedCompletionDate" TIMESTAMP,
  priority VARCHAR(10),
  "priorityNote" VARCHAR(500),
  "priorityRank" INT,
  "priorityAssignedById" INT,
  "priorityAssignedAt" TIMESTAMP,
  "wtyComment" VARCHAR(1000),
  "rejectionNote" VARCHAR(1000),
  "scmDecision" VARCHAR(20) CHECK ("scmDecision" IN ('LOAD_WITHOUT', 'WAIT', 'REORGANIZE', 'NEW_TRIP')),
  "scmDecisionNote" VARCHAR(1000),
  "scmDecisionAt" TIMESTAMP,
  "scmDecisionById" INT,
  "archivedAt" TIMESTAMP,
  "archivedById" INT,
  "createdAt" TIMESTAMP DEFAULT (NOW() AT TIME ZONE 'UTC'),
  "updatedAt" TIMESTAMP DEFAULT (NOW() AT TIME ZONE 'UTC'),
  CONSTRAINT "FK_Unit_Status" FOREIGN KEY ("statusId") REFERENCES "UnitStatus"(id),
  CONSTRAINT "FK_Unit_RegisteredBy" FOREIGN KEY ("registeredById") REFERENCES "User"(id),
  CONSTRAINT "FK_Unit_Provider" FOREIGN KEY ("providerId") REFERENCES "Provider"(id),
  CONSTRAINT "FK_Unit_ScmDecisionBy" FOREIGN KEY ("scmDecisionById") REFERENCES "User"(id),
  CONSTRAINT "FK_Unit_ArchivedBy" FOREIGN KEY ("archivedById") REFERENCES "User"(id),
  CONSTRAINT "UQ_Unit_Vin_Plant" UNIQUE (vin, plant)
);

CREATE INDEX "IX_Unit_VIN" ON "Unit"(vin);
CREATE INDEX "IX_Unit_Status" ON "Unit"("statusId");
CREATE INDEX "IX_Unit_Provider" ON "Unit"("providerId");
CREATE INDEX "IX_Unit_CreatedAt" ON "Unit"("createdAt");
CREATE INDEX "IX_Unit_Priority" ON "Unit"(priority);
CREATE INDEX "IX_Unit_Plant" ON "Unit"(plant);
CREATE INDEX "IX_Unit_ScmDecision" ON "Unit"("scmDecision");
CREATE INDEX "IX_Unit_ScmDecisionAt" ON "Unit"("scmDecisionAt");

COMMENT ON COLUMN "Unit"."providerId" IS 'ID del proveedor asociado. Se asigna automáticamente cuando un carrier reporta una unidad, o manualmente cuando WWS reporta una unidad para notificar al carrier correspondiente';
COMMENT ON COLUMN "Unit".plant IS 'Planta donde está registrada la unidad (A1 o A2)';
COMMENT ON COLUMN "Unit"."wtyComment" IS 'Comentario opcional de WWS al enviar unidad a validación WTY';
COMMENT ON COLUMN "Unit"."rejectionNote" IS 'Motivo de rechazo cuando Carrier rechaza la unidad';
COMMENT ON COLUMN "Unit"."scmDecision" IS 'Decisión de SCM para unidades UNAVAILABLE';
COMMENT ON COLUMN "Unit"."scmDecisionNote" IS 'Nota opcional de SCM para sustentar la decisión';
COMMENT ON COLUMN "Unit"."scmDecisionAt" IS 'Fecha/hora en que SCM registró la decisión';
COMMENT ON COLUMN "Unit"."scmDecisionById" IS 'Usuario SCM que registró la decisión';
COMMENT ON COLUMN "Unit"."archivedAt" IS 'Fecha cuando la unidad fue archivada';
COMMENT ON COLUMN "Unit"."archivedById" IS 'Usuario que archivó la unidad';

-- Tabla de Solicitudes de Borrado de Unidad (Carrier/WWS -> SCM)
CREATE TABLE "UnitDeletionRequest" (
  id SERIAL PRIMARY KEY,
  "unitId" INT NOT NULL,
  "requestedById" INT NOT NULL,
  reason VARCHAR(500) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
  "decisionNote" VARCHAR(1000),
  "decidedById" INT,
  "requestedAt" TIMESTAMP DEFAULT (NOW() AT TIME ZONE 'UTC'),
  "decidedAt" TIMESTAMP,
  "createdAt" TIMESTAMP DEFAULT (NOW() AT TIME ZONE 'UTC'),
  "updatedAt" TIMESTAMP DEFAULT (NOW() AT TIME ZONE 'UTC'),
  CONSTRAINT "FK_UnitDeletionRequest_Unit" FOREIGN KEY ("unitId") REFERENCES "Unit"(id) ON DELETE CASCADE,
  CONSTRAINT "FK_UnitDeletionRequest_RequestedBy" FOREIGN KEY ("requestedById") REFERENCES "User"(id),
  CONSTRAINT "FK_UnitDeletionRequest_DecidedBy" FOREIGN KEY ("decidedById") REFERENCES "User"(id)
);

CREATE INDEX "IX_UnitDeletionRequest_UnitId" ON "UnitDeletionRequest"("unitId");
CREATE INDEX "IX_UnitDeletionRequest_Status" ON "UnitDeletionRequest"(status);
CREATE INDEX "IX_UnitDeletionRequest_RequestedAt" ON "UnitDeletionRequest"("requestedAt");

-- Tabla de Defectos de Unidad
CREATE TABLE "UnitDefect" (
  id SERIAL PRIMARY KEY,
  "unitId" INT NOT NULL,
  "defectType" VARCHAR(100) NOT NULL,
  zone VARCHAR(100) NOT NULL,
  "gradeId" INT NOT NULL,
  description VARCHAR(500),
  "repairCatalogId" INT,
  "registeredById" INT NOT NULL,
  "isResolved" BOOLEAN DEFAULT FALSE,
  "isActive" BOOLEAN DEFAULT TRUE,
  "overriddenByWws" BOOLEAN DEFAULT FALSE,
  "wwsVersion" VARCHAR(50),
  "photoUrls" TEXT[] DEFAULT ARRAY[]::TEXT[],
  "createdAt" TIMESTAMP DEFAULT (NOW() AT TIME ZONE 'UTC'),
  "updatedAt" TIMESTAMP DEFAULT (NOW() AT TIME ZONE 'UTC'),
  CONSTRAINT "FK_Defect_Unit" FOREIGN KEY ("unitId") REFERENCES "Unit"(id) ON DELETE CASCADE,
  CONSTRAINT "FK_Defect_Grade" FOREIGN KEY ("gradeId") REFERENCES "DefectGrade"(id),
  CONSTRAINT "FK_Defect_UnitModel" FOREIGN KEY ("repairCatalogId") REFERENCES "UnitModel"(id),
  CONSTRAINT "FK_Defect_RegisteredBy" FOREIGN KEY ("registeredById") REFERENCES "User"(id)
);

CREATE INDEX "IX_Defect_UnitId" ON "UnitDefect"("unitId");
CREATE INDEX "IX_Defect_GradeId" ON "UnitDefect"("gradeId");
CREATE INDEX "IX_Defect_IsResolved" ON "UnitDefect"("isResolved");
CREATE INDEX "IX_Defect_IsActive" ON "UnitDefect"("isActive");

COMMENT ON COLUMN "UnitDefect"."isActive" IS 'Indica si el defecto está activo. Permite soft-delete cuando WWS reemplaza un defecto.';
COMMENT ON COLUMN "UnitDefect"."overriddenByWws" IS 'Marca si este defecto fue reemplazado por una versión de WWS';
COMMENT ON COLUMN "UnitDefect"."wwsVersion" IS 'Versión/timestamp cuando WWS modificó o creó este defecto';
COMMENT ON COLUMN "UnitDefect"."photoUrls" IS 'Lista de URLs públicas de evidencia fotográfica por defecto';

-- Tabla de Eventos de Unidad (Consolidada - reemplaza UnitStatusHistory)
-- Esta tabla agrupa múltiples tipos de cambios en un solo registro usando JSONB
CREATE TABLE "UnitEvent" (
  id SERIAL PRIMARY KEY,
  "unitId" INT NOT NULL,
  "eventType" VARCHAR(50) NOT NULL, -- 'STATUS_CHANGE', 'DEFECT_ADDED', 'DEFECT_UPDATED', 'PRIORITY_UPDATED', etc.
  "eventData" JSONB NOT NULL, -- Toda la información del evento en formato flexible
  "performedById" INT NOT NULL,
  "createdAt" TIMESTAMP DEFAULT (NOW() AT TIME ZONE 'UTC'),
  CONSTRAINT "FK_Event_Unit" FOREIGN KEY ("unitId") REFERENCES "Unit"(id) ON DELETE CASCADE,
  CONSTRAINT "FK_Event_User" FOREIGN KEY ("performedById") REFERENCES "User"(id)
);

CREATE INDEX "IX_Event_UnitId" ON "UnitEvent"("unitId");
CREATE INDEX "IX_Event_Type" ON "UnitEvent"("eventType");
CREATE INDEX "IX_Event_CreatedAt" ON "UnitEvent"("createdAt");
CREATE INDEX "IX_Event_Data" ON "UnitEvent" USING GIN("eventData"); -- Permite queries rápidas en JSONB

-- Vista de compatibilidad para código que aún usa UnitStatusHistory
CREATE OR REPLACE VIEW "UnitStatusHistory" AS
SELECT 
  id,
  "unitId",
  CASE 
    WHEN "eventData"->>'previousStatusId' IS NOT NULL 
    THEN ("eventData"->>'previousStatusId')::INT 
    ELSE NULL 
  END as "previousStatusId",
  ("eventData"->>'newStatusId')::INT as "newStatusId",
  "performedById" as "changedById",
  "createdAt" as "changedAt"
FROM "UnitEvent"
WHERE "eventType" = 'STATUS_CHANGE';

-- Tabla de Notificaciones
CREATE TABLE "Notification" (
  id SERIAL PRIMARY KEY,
  "userId" INT NOT NULL,
  "unitId" INT NOT NULL,
  type VARCHAR(50) NOT NULL,
  message VARCHAR(500),
  "isRead" BOOLEAN DEFAULT FALSE,
  "createdAt" TIMESTAMP DEFAULT (NOW() AT TIME ZONE 'UTC'),
  CONSTRAINT "FK_Notification_User" FOREIGN KEY ("userId") REFERENCES "User"(id),
  CONSTRAINT "FK_Notification_Unit" FOREIGN KEY ("unitId") REFERENCES "Unit"(id) ON DELETE CASCADE
);

CREATE INDEX "IX_Notification_UserId" ON "Notification"("userId");
CREATE INDEX "IX_Notification_IsRead" ON "Notification"("isRead");
CREATE INDEX "IX_Notification_CreatedAt" ON "Notification"("createdAt");

-- Seed data: Unit Models
INSERT INTO "UnitModel" (code, name, "isActive") VALUES
  ('KICKS', 'KICKS', TRUE),
  ('SENTRA', 'SENTRA', TRUE),
  ('VERSA', 'VERSA', TRUE);
