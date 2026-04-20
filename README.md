# Documentación del Esquema de Base de Datos
## Sistema de Gestión de Body Shop - Nissan

## Visión General

Este esquema de base de datos PostgreSQL gestiona el flujo operacional del Body Shop de Nissan, permitiendo el seguimiento de unidades vehiculares desde su reporte inicial hasta su liberación final, involucrando múltiples roles (WWS, SCM, BODY, CARRIER, WTY) y plantas (A1, A2).

### Características Principales:
- **Multi-tenant**: Soporte para múltiples plantas (A1, A2)
- **Sistema de roles**: 7 roles diferentes con permisos específicos
- **Trazabilidad completa**: Historial de eventos mediante JSONB
- **Notificaciones en tiempo real**: Sistema de notificaciones entre roles
- **Gestión de defectos**: Catálogo de modelos de unidad administrado por SCM

---

## Diagrama de Relaciones

```
┌──────────┐
│   Role   │
└────┬─────┘
     │
     │ FK: roleId
     ▼
┌──────────┐        ┌────────────┐
│   User   │◄───────┤  Provider  │
└────┬─────┘        └─────┬──────┘
     │                    │
     │ FK: registeredById │ FK: providerId
     │                    │
     ▼                    ▼
┌───────────────────────────────────┐      ┌──────────────┐
│            Unit                   │◄─────┤  UnitStatus  │
└────┬──────────────────┬───────────┘      └──────────────┘
     │                  │
     │ FK: unitId       │ FK: unitId
     ▼                  ▼
┌──────────┐      ┌──────────────┐
│UnitDefect│      │  UnitEvent   │
└────┬─────┘      └──────────────┘
     │
     │ FK: gradeId
     ▼
┌──────────────┐      ┌────────────────┐
│ DefectGrade  │      │   UnitModel    │
└──────────────┘      └────────────────┘

┌─────────────────────┐
│ UnitDeletionRequest │◄────(FK: unitId, requestedById, decidedById)
└─────────────────────┘

┌──────────────┐
│ Notification │◄────(FK: userId, unitId)
└──────────────┘
```

---

## Tablas

### 1. Role

**Propósito**: Define los roles del sistema con sus permisos y responsabilidades.

#### Campos:
| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | SERIAL (PK) | Identificador único del rol |
| `name` | VARCHAR(50) UNIQUE | Nombre del rol |

#### Roles Predefinidos:
| ID | Nombre  | Descripción |
|----|---------|-------------|
| 1  | WWS     | Reporta y envia unidades a reparacion o libera dependiendo del criterio |
| 2  | SCM     | Supply Chain Management - Gestiona logística |
| 3  | BODY    | Body Shop - Repara unidades |
| 4  | CARRIER | Transportista - Entrega, Acepta/rechaza unidades reparadas|
| 5  | ADMIN   | Administrador del sistema |
| 6  | WTY     | Warranty - Valida unidades para garantía |
| 7  | SCM_QUALITY | Control de calidad SCM |

#### Uso en el Código:
- **Constantes**: `backend/src/constants/index.ts` → `ROLE_IDS`
- **Middleware**: `backend/src/middleware/roleGuard.ts`
- **Autenticación**: `backend/src/services/AuthService.ts`
- **Permisos**: `body-app/lib/permissions.ts`

---

### 2. Provider

**Propósito**: Gestiona información de proveedores/transportistas responsables de las unidades.

#### Campos:
| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | SERIAL (PK) | Identificador único del proveedor |
| `name` | VARCHAR(255) UNIQUE | Nombre del proveedor |
| `code` | VARCHAR(50) | Código interno del proveedor |
| `createdAt` | TIMESTAMP | Fecha de creación |
| `updatedAt` | TIMESTAMP | Fecha de última actualización |

#### Relaciones:
- **User.providerId** → Provider.id (muchos a uno)
- **Unit.providerId** → Provider.id (muchos a uno)

#### Uso en el Código:
- **Repository**: `backend/src/repositories/ProviderRepository.ts`
- **Service**: `backend/src/services/ProviderService.ts`
- **Controller**: `backend/src/controllers/ProviderController.ts`
- **Rutas**: `backend/src/routes/providers.ts`
- **Frontend**: `body-app/components/forms/ReportForm.tsx`

---

### 3. User

**Propósito**: Almacena información de usuarios del sistema con sus credenciales y permisos.

#### Campos:
| Campo | Tipo | Restricciones | Descripción |
|-------|------|---------------|-------------|
| `id` | SERIAL (PK) | - | Identificador único |
| `email` | VARCHAR(255) | UNIQUE, NOT NULL | Email del usuario (login) |
| `password` | VARCHAR(255) | NOT NULL | Hash bcrypt de la contraseña |
| `name` | VARCHAR(255) | NOT NULL | Nombre completo |
| `roleId` | INT | FK → Role.id | Rol asignado |
| `providerId` | INT | FK → Provider.id, NULL | Proveedor asociado (solo CARRIER) |
| `plant` | VARCHAR(2) | 'A1', 'A2', NULL | Planta asignada |
| `createdAt` | TIMESTAMP | DEFAULT NOW() | Fecha de creación |
| `updatedAt` | TIMESTAMP | DEFAULT NOW() | Última actualización |

#### Índices:
- `IX_User_Email` en `email` - Búsqueda rápida en login
- `IX_User_RoleId` en `roleId` - Filtrado por rol
- `IX_User_Plant` en `plant` - Filtrado por planta

#### Relaciones:
- **FK_User_Role**: roleId → Role.id
- **FK_User_Provider**: providerId → Provider.id
- **Unit.registeredById** → User.id (inversa)
- **UnitEvent.performedById** → User.id (inversa)

#### Uso en el Código:
- **Repository**: `backend/src/repositories/UserRepository.ts`
- **Service**: `backend/src/services/UserService.ts`
  - `findByEmail()` - Búsqueda en login
  - `findById()` - Datos del usuario autenticado
  - `findByRoleIds()` - Notificaciones por rol
- **Controller**: `backend/src/controllers/UserController.ts`
- **Auth**: `backend/src/services/AuthService.ts`
- **Middleware**: `backend/src/middleware/auth.ts` (token validation)

---

### 4. UnitStatus

**Propósito**: Define los estados posibles en el ciclo de vida de una unidad.

#### Campos:
| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | SERIAL (PK) | Identificador único del estado |
| `name` | VARCHAR(50) UNIQUE | Nombre del estado |

#### Estados Predefinidos:
| Estado | Descripción | Rol Responsable |
|--------|-------------|-----------------|
| `REPORTED` | Unidad reportada con defectos | WWS |
| `SENT` | Enviada por WWS para validación SCM | WWS |
| `DELIVERED` | Entregada por carrier | CARRIER |
| `RECEIVED` | Recibida en Body Shop | BODY |
| `IN_REPAIR` | En proceso de reparación | BODY |
| `RELEASED` | Liberada por Body Shop | BODY |
| `WTY_PENDING` | Pendiente de validación Warranty | WTY |
| `WTY_RELEASED` | Liberada por Warranty | WTY |
| `WWS_RELEASED` | Liberada final por WWS | WWS |
| `ACCEPTED` | Aceptada por carrier | CARRIER |
| `REJECTED` | Rechazada por carrier | CARRIER |
| `UNAVAILABLE` | No disponible hoy | Cualquiera |
| `ARCHIVED` | Archivada histórico | ADMIN |

#### Relaciones:
- **Unit.statusId** → UnitStatus.id (muchos a uno)

#### Uso en el Código:
- **Repository**: `backend/src/repositories/UnitRepository.ts`
  - `findByStatusName()` - Filtrado por estado
- **Service**: `backend/src/services/UnitService.ts`
  - Transiciones de estado según rol
- **Frontend**: `body-app/components/units/` - Visualización de estados

---

### 5. DefectGrade

**Propósito**: Clasifica la severidad de los defectos en tres niveles.

#### Campos:
| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | SERIAL (PK) | Identificador único |
| `code` | VARCHAR(10) UNIQUE | Código de grado (V1, V2, V3) |
| `description` | VARCHAR(100) | Descripción del grado |

#### Grados Predefinidos:
| Código | Descripción | Impacto |
|--------|-------------|---------|
| `V1` | Defecto grave - Reparación extensa | 8-12 horas |
| `V2` | Defecto moderado - Reparación media | 4-6 horas |
| `V3` | Defecto leve - Reparación rápida | 2-3 horas |

#### Relaciones:
- **UnitDefect.gradeId** → DefectGrade.id
- **UnitDefect.repairCatalogId** → UnitModel.id

#### Uso en el Código:
- **Constantes**: `backend/src/constants/index.ts` → `VALID_GRADES`
- **Repository**: `backend/src/repositories/UnitRepository.ts`
- **Frontend**: `body-app/components/forms/ReportForm.tsx` - Selector de grado

---

### 6. UnitModel

**Propósito**: Catálogo de modelos de unidad gestionado por SCM para configuración operativa.

#### Campos:
| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | SERIAL (PK) | Identificador único |
| `code` | VARCHAR(50) UNIQUE | Código único de modelo |
| `name` | VARCHAR(120) | Nombre del modelo |
| `isActive` | BOOLEAN | Habilita/deshabilita el modelo |
| `createdAt` | TIMESTAMP | Fecha de creación |
| `updatedAt` | TIMESTAMP | Última actualización |

#### Restricciones:
- **UQ_UnitModel_Code**: UNIQUE(code) - Evita códigos duplicados

#### Índices:
- `IX_UnitModel_IsActive` en `isActive` - Filtrado de modelos habilitados

#### Relaciones:
- **UnitDefect.repairCatalogId** → UnitModel.id (inversa)

#### Uso en el Código:
- **Python API**: `backend_Python/app/routes/unit_models.py`
- **Frontend**: `body-app/app/profile/page.tsx` - Configuración SCM/ADMIN

---

### 7. Unit

**Propósito**: Tabla principal que representa cada unidad vehicular en el sistema.

#### Campos Principales:
| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | SERIAL (PK) | Identificador único |
| `vin` | VARCHAR(50) | Número de identificación vehicular (17 chars) |
| `market` | VARCHAR(100) | Mercado destino (USA, CANADA, MEXICO) |
| `lane` | VARCHAR(50) | Línea/carril de producción |
| `statusId` | INT (FK) | Estado actual de la unidad |
| `providerId` | INT (FK) | Proveedor/carrier responsable |
| `plant` | VARCHAR(2) | Planta (A1 o A2) |
| `registeredById` | INT (FK) | Usuario que registró la unidad |

#### Campos de Disponibilidad:
| Campo | Tipo | Descripción |
|-------|------|-------------|
| `isAvailableToday` | BOOLEAN | Disponible para trabajo hoy (uso Body) |

#### Campos de Estimación:
| Campo | Tipo | Descripción |
|-------|------|-------------|
| `estimatedRepairHours` | DECIMAL(5,2) | Suma de horas estimadas de defectos |
| `estimatedCompletionDate` | TIMESTAMP | Fecha estimada de finalización |

#### Campos de Prioridad:
| Campo | Tipo | Descripción |
|-------|------|-------------|
| `priority` | VARCHAR(10) | Nivel de prioridad (HIGH, NORMAL, LOW) |
| `priorityNote` | VARCHAR(500) | Justificación de la prioridad |
| `priorityRank` | INT | Orden de prioridad (1=más urgente) |
| `priorityAssignedById` | INT | Usuario que asignó la prioridad |
| `priorityAssignedAt` | TIMESTAMP | Fecha de asignación de prioridad |

#### Campos de Validación:
| Campo | Tipo | Descripción |
|-------|------|-------------|
| `wtyComment` | VARCHAR(1000) | Comentario de WWS al enviar a WTY |
| `rejectionNote` | VARCHAR(1000) | Motivo de rechazo por Carrier |

#### Campos de Auditoría:
| Campo | Tipo | Descripción |
|-------|------|-------------|
| `archivedAt` | TIMESTAMP | Fecha de archivado |
| `archivedById` | INT (FK) | Usuario que archivó |
| `createdAt` | TIMESTAMP | Fecha de registro inicial |
| `updatedAt` | TIMESTAMP | Última modificación |

#### Restricciones:
- **UQ_Unit_Vin_Plant**: UNIQUE(vin, plant) - Un VIN por planta
- **CHECK**: plant IN ('A1', 'A2', NULL)

#### Índices:
- `IX_Unit_VIN` - Búsqueda por VIN
- `IX_Unit_Status` - Filtrado por estado
- `IX_Unit_Provider` - Filtrado por proveedor
- `IX_Unit_CreatedAt` - Ordenamiento temporal
- `IX_Unit_Priority` - Ordenamiento por prioridad
- `IX_Unit_Plant` - Filtrado por planta

#### Relaciones:
| FK | Referencias | Descripción |
|----|-------------|-------------|
| `FK_Unit_Status` | statusId → UnitStatus.id | Estado actual |
| `FK_Unit_RegisteredBy` | registeredById → User.id | Quién la creó |
| `FK_Unit_Provider` | providerId → Provider.id | Carrier asignado |
| `FK_Unit_ArchivedBy` | archivedById → User.id | Quién la archivó |

#### Uso en el Código:

**Backend**:
- **Repository**: `backend/src/repositories/UnitRepository.ts`
  - `findAll()` - Listado con filtros
  - `findById()` - Detalle de unidad
  - `findByVin()` - Búsqueda por VIN
  - `findByStatusName()` - Filtrado por estado
  - `create()` - Crear nueva unidad
  - `updateStatus()` - Cambiar estado
  - `updatePriority()` - Actualizar prioridad

- **Service**: `backend/src/services/UnitService.ts`
  - Lógica de negocio de transiciones
  - Validaciones de permisos por rol
  - Cálculo de tiempos estimados

- **Controller**: `backend/src/controllers/UnitController.ts`
  - GET /units
  - GET /units/:id
  - POST /units
  - PUT /units/:id/status
  - PUT /units/:id/priority
  - GET /units/deletion-requests (SCM)
  - PUT /units/deletion-requests/:requestId/decision (SCM)
  - POST /units/:id/deletion-requests (CARRIER, WWS)

**Frontend**:
- `body-app/app/reportar_unidad/page.tsx` - Reportar nueva unidad
- `body-app/app/recibir_unidades/page.tsx` - Recepción BODY
- `body-app/app/aceptar_unidades/page.tsx` - Aceptar/rechazar CARRIER
- `body-app/app/reparar_unidades/page.tsx` - Gestión de reparaciones
- `body-app/app/prioridad_reparaciones/page.tsx` - Asignación de prioridades
- `body-app/components/units/` - Componentes de visualización

---

### 8. UnitDeletionRequest

**Propósito**: Registra solicitudes de borrado físico de unidades reportadas por error, con flujo de aprobación/rechazo por SCM.

#### Campos:
| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | SERIAL (PK) | Identificador único |
| `unitId` | INT (FK) | Unidad solicitada para borrado |
| `requestedById` | INT (FK) | Usuario solicitante (CARRIER o WWS) |
| `reason` | VARCHAR(500) | Justificación de la solicitud |
| `status` | VARCHAR(20) | Estado (`PENDING`, `APPROVED`, `REJECTED`) |
| `decisionNote` | VARCHAR(1000) | Comentario de decisión SCM |
| `decidedById` | INT (FK) | Usuario SCM que decide |
| `requestedAt` | TIMESTAMP | Fecha de solicitud |
| `decidedAt` | TIMESTAMP | Fecha de decisión |
| `createdAt` | TIMESTAMP | Fecha de creación |
| `updatedAt` | TIMESTAMP | Última actualización |

#### Índices:
- `IX_UnitDeletionRequest_UnitId` - Búsqueda por unidad
- `IX_UnitDeletionRequest_Status` - Filtro por estado
- `IX_UnitDeletionRequest_RequestedAt` - Orden temporal

#### Relaciones:
| FK | Referencias | Acción |
|----|-------------|--------|
| `FK_UnitDeletionRequest_Unit` | unitId → Unit.id | ON DELETE CASCADE |
| `FK_UnitDeletionRequest_RequestedBy` | requestedById → User.id | - |
| `FK_UnitDeletionRequest_DecidedBy` | decidedById → User.id | - |

#### Reglas de Negocio Implementadas:
- Solo CARRIER y WWS pueden crear solicitudes.
- Solo SCM puede aprobar o rechazar.
- Si SCM aprueba, la unidad se borra físicamente.
- Si SCM rechaza, la unidad conserva su estado actual.

#### Uso en el Código:
- **Node**:
  - Repository: `backend/src/repositories/UnitDeletionRequestRepository.ts`
  - Service: `backend/src/services/UnitDeletionRequestService.ts`
  - Controller: `backend/src/controllers/UnitDeletionRequestController.ts`
  - Routes: `backend/src/routes/units.ts`
- **Python**:
  - Repository: `backend_Python/app/repositories/unit_deletion_request_repository.py`
  - Service: `backend_Python/app/services/unit_deletion_request_service.py`
  - Controller: `backend_Python/app/controllers/unit_deletion_request_controller.py`
  - Routes: `backend_Python/app/routes/units.py`

---

### 9. UnitDefect

**Propósito**: Registra cada defecto individual encontrado en una unidad.

#### Campos:
| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | SERIAL (PK) | Identificador único |
| `unitId` | INT (FK) | Unidad afectada |
| `defectType` | VARCHAR(100) | Tipo de defecto |
| `zone` | VARCHAR(100) | Zona del vehículo |
| `gradeId` | INT (FK) | Grado de severidad |
| `description` | VARCHAR(500) | Descripción detallada |
| `repairCatalogId` | INT (FK) | Referencia al modelo de unidad (si aplica) |
| `registeredById` | INT (FK) | Usuario que registró |
| `isResolved` | BOOLEAN | Defecto resuelto |
| `isActive` | BOOLEAN | Indica si el defecto está activo |
| `overriddenByWws` | BOOLEAN | Marca si fue reemplazado por WWS |
| `wwsVersion` | VARCHAR(50) | Versión/marca temporal de ajuste WWS |
| `photoUrls` | TEXT[] | Lista de URLs de fotos de evidencia del defecto |
| `createdAt` | TIMESTAMP | Fecha de registro |
| `updatedAt` | TIMESTAMP | Última actualización |

#### Índices:
- `IX_Defect_UnitId` - Join con Unit
- `IX_Defect_GradeId` - Filtrado por severidad
- `IX_Defect_IsResolved` - Filtrar pendientes/resueltos
- `IX_Defect_IsActive` - Filtrar defectos vigentes

#### Relaciones:
| FK | Referencias | Acción |
|----|-------------|--------|
| `FK_Defect_Unit` | unitId → Unit.id | ON DELETE CASCADE |
| `FK_Defect_Grade` | gradeId → DefectGrade.id | - |
| `FK_Defect_UnitModel` | repairCatalogId → UnitModel.id | - |
| `FK_Defect_RegisteredBy` | registeredById → User.id | - |

#### Uso en el Código:
- **Repository**: Consultas embebidas en `UnitRepository.ts`
  - `findByStatusName()` incluye defectos
- **Service**: `backend/src/services/UnitService.ts`
  - Creación de defectos al reportar unidad
  - Marcado de defectos como resueltos
- **Frontend**: `body-app/components/forms/ReportForm.tsx`
  - Formulario de reporte múltiple de defectos

---

### 10. UnitEvent

**Propósito**: Sistema de auditoría consolidado que registra todos los eventos/cambios en una unidad usando JSONB flexible.

#### Campos:
| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | SERIAL (PK) | Identificador único |
| `unitId` | INT (FK) | Unidad afectada |
| `eventType` | VARCHAR(50) | Tipo de evento |
| `eventData` | JSONB | Datos del evento (formato flexible) |
| `performedById` | INT (FK) | Usuario que ejecutó la acción |
| `createdAt` | TIMESTAMP | Fecha del evento |

#### Tipos de Eventos (`eventType`):
| Tipo | Descripción | Datos en `eventData` |
|------|-------------|---------------------|
| `STATUS_CHANGE` | Cambio de estado | `{ previousStatusId, newStatusId, previousStatus, newStatus }` |
| `DEFECT_ADDED` | Agregado defecto | `{ defectType, zone, gradeId }` |
| `DEFECT_UPDATED` | Defecto actualizado | `{ defectId, changes }` |
| `PRIORITY_UPDATED` | Prioridad modificada | `{ oldPriority, newPriority, note }` |
| `SCM_DECISION` | Decisión SCM sobre unidad | `{ decision, decisionNote }` |
| `REPAIR_TIME_UPDATED` | Ajuste de tiempo de reparación | `{ estimatedRepairHours, estimatedCompletionDate }` |
| `NOTE_ADDED` | Nota operativa agregada | `{ note, context }` |
| `UNIT_DELETION_REQUESTED` | Solicitud de borrado creada | `{ requestId, reason }` |
| `UNIT_DELETION_DECIDED` | Solicitud de borrado decidida | `{ requestId, decision }` |

#### Índices:
- `IX_Event_UnitId` - Historial por unidad
- `IX_Event_Type` - Filtrado por tipo
- `IX_Event_CreatedAt` - Ordenamiento cronológico
- `IX_Event_Data` GIN - Búsqueda en JSONB

#### Relaciones:
| FK | Referencias | Acción |
|----|-------------|--------|
| `FK_Event_Unit` | unitId → Unit.id | ON DELETE CASCADE |
| `FK_Event_User` | performedById → User.id | - |

#### Uso en el Código:
- **Repository**: `backend/src/repositories/StatusHistoryRepository.ts`
  - Consultas filtradas por rango de fechas
  - Búsqueda por usuario, mercado, VIN
- **Service**: Creación automática en cada transición
- **Realtime**: `backend/src/realtime/unitEventStream.ts` - SSE events
- **Frontend**: `body-app/app/logs/page.tsx` - Visualización de historial

---

### 11. Notification

**Propósito**: Sistema de notificaciones entre usuarios y roles.

#### Campos:
| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | SERIAL (PK) | Identificador único |
| `userId` | INT (FK) | Usuario destinatario |
| `unitId` | INT (FK) | Unidad relacionada |
| `type` | VARCHAR(50) | Tipo de notificación |
| `message` | VARCHAR(500) | Mensaje de la notificación |
| `isRead` | BOOLEAN | Leída o no |
| `createdAt` | TIMESTAMP | Fecha de creación |

#### Tipos de Notificaciones (`type`):
- `UNIT_REPORTED` - Nueva unidad reportada
- `UNIT_DELIVERED` - Unidad entregada
- `UNIT_RELEASED` - Unidad liberada
- `WTY_PENDING` - Unidad enviada a validación WTY
- `WTY_RELEASED` - Unidad aprobada por WTY
- `UNIT_WWS_RELEASED` - Unidad liberada por WWS
- `UNIT_ACCEPTED` - Aceptada por carrier
- `UNIT_REJECTED` - Rechazada por carrier
- `UNIT_RETURNED_TO_SENT` - Unidad regresada a nivelación WWS
- `UNIT_ARCHIVED` - Unidad archivada
- `UNIT_DELETION_REQUESTED` - Solicitud de borrado enviada a SCM
- `UNIT_DELETION_APPROVED` - Solicitud aprobada
- `UNIT_DELETION_REJECTED` - Solicitud rechazada
- `STATUS_CHANGED` - Cambio de estatus
- `DEFECT_ADDED` - Defecto agregado
- `REPAIR_ESTIMATED` - Tiempo de reparación estimado

#### Índices:
- `IX_Notification_UserId` - Notificaciones por usuario
- `IX_Notification_IsRead` - Filtrar no leídas
- `IX_Notification_CreatedAt` - Ordenamiento temporal

#### Relaciones:
| FK | Referencias | Acción |
|----|-------------|--------|
| `FK_Notification_User` | userId → User.id | - |
| `FK_Notification_Unit` | unitId → Unit.id | ON DELETE CASCADE |

#### Uso en el Código:
- **Repository**: `backend/src/repositories/NotificationRepository.ts`
  - `createMany()` - Notificación múltiple
  - `listByUser()` - Listado por usuario
  - `markRead()` - Marcar como leída
  - `markAllRead()` - Marcar todas
  - `deleteById()` - Eliminar notificación

- **Service**: `backend/src/services/NotificationService.ts`
  - Lógica de creación según rol
  - Envío a usuarios específicos

- **Controller**: `backend/src/controllers/NotificationController.ts`
  - GET /notifications (usuario actual)
  - PUT /notifications/:id/read
  - POST /notifications/read-all
  - DELETE /notifications/:id

- **Realtime**: `backend/src/realtime/notificationHub.ts` - WebSocket (`/ws/notifications`)

- **Frontend**: 
  - `body-app/components/layout/NotificationBell.tsx` - Campana de notificaciones
  - Realtime updates via WebSocket

---

## Vistas

### UnitStatusHistory (Vista de Compatibilidad)

**Propósito**: Proporciona retrocompatibilidad con código legacy que espera una tabla dedicada de historial de estados.

**Definición**:
```sql
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
```

**Campos Expuestos**:
- `id` - ID del evento
- `unitId` - ID de la unidad
- `previousStatusId` - Estado anterior
- `newStatusId` - Estado nuevo
- `changedById` - Usuario que hizo el cambio
- `changedAt` - Fecha del cambio

**Uso**: Permite consultas SQL sin modificar código que referenciaba la tabla original.

---

## Índices y Optimizaciones

### Estrategia de Indexación

#### Índices B-Tree (por defecto):
- **Email de usuarios**: Búsqueda exacta en login
- **VIN de unidades**: Búsqueda frecuente por identificador
- **Foreign Keys**: Optimización de JOINs
- **Campos de filtrado**: status, plant, provider

#### Índices GIN (para JSONB):
- **UnitEvent.eventData**: Permite búsquedas rápidas dentro del JSON
  ```sql
  WHERE eventData @> '{"newStatus": "RELEASED"}'
  ```

#### Índices Compuestos Implícitos:
- **UNIQUE(vin, plant)**: Evita duplicados y acelera búsquedas combinadas
- **UNIQUE(defectType, zone, gradeId)**: Catálogo sin duplicados

### Recomendaciones de Performance:

1. **Parámetros LIMIT**: Todas las consultas usan paginación (default 50-200)
2. **WHERE 1=1**: Construcción dinámica de filtros en repositories
3. **JOIN selectivo**: Solo incluir defectos cuando se necesitan
4. **CASCADE DELETE**: UnitDefect, UnitEvent, Notification y UnitDeletionRequest se eliminan automáticamente

---

## Uso en el Código

### Backend Structure

```
backend/src/
├── repositories/        # Acceso a datos (SQL queries)
│   ├── UnitRepository.ts
│   ├── UnitDeletionRequestRepository.ts
│   ├── UserRepository.ts
│   ├── NotificationRepository.ts
│   ├── ProviderRepository.ts
│   └── StatusHistoryRepository.ts
│
├── services/           # Lógica de negocio
│   ├── UnitService.ts
│   ├── UnitDeletionRequestService.ts
│   ├── AuthService.ts
│   ├── NotificationService.ts
│   └── ProviderService.ts
│
├── controllers/        # Endpoints HTTP
│   ├── UnitController.ts
│   ├── UnitDeletionRequestController.ts
│   ├── AuthController.ts
│   ├── NotificationController.ts
│   └── DashboardController.ts
│
└── routes/            # Definición de rutas
    ├── units.ts
    ├── auth.ts
    ├── notifications.ts
    └── events.ts (SSE)
```

### Flujo de Datos Típico:

```
HTTP Request
    ↓
Route → Controller
    ↓
Service (validaciones, lógica)
    ↓
Repository (SQL)
    ↓
Database PostgreSQL
```

### Ejemplo: Reportar Unidad

1. **Frontend**: `body-app/app/reportar_unidad/page.tsx`
   ```typescript
   const response = await api.post('/units', {
     vin, market, lane, plant, providerId,
     defects: [{ defectType, zone, gradeId }]
   });
   ```

2. **Route**: `backend/src/routes/units.ts`
   ```typescript
   router.post('/', requireAuth, UnitController.create);
   ```

3. **Controller**: `backend/src/controllers/UnitController.ts`
   ```typescript
   const unit = await UnitService.createUnit(data, req.user);
   ```

4. **Service**: `backend/src/services/UnitService.ts`
   ```typescript
   // Valida permisos, crea Unit, UnitDefects, UnitEvent
   // Calcula estimatedRepairHours
   // Envía notificaciones
   ```

5. **Repository**: `backend/src/repositories/UnitRepository.ts`
   ```typescript
   // Ejecuta INSERTs en Unit, UnitDefect
   ```

6. **Notifications**: `backend/src/services/NotificationService.ts`
   ```typescript
   // Notifica a usuarios de rol BODY/SCM
   ```

### Tablas por Módulo:

| Módulo | Tablas Principales | Archivos Clave |
|--------|-------------------|----------------|
| **Autenticación** | User, Role, RefreshToken | AuthService.ts, AuthController.ts |
| **Unidades** | Unit, UnitStatus, UnitDefect, UnitDeletionRequest | UnitService.ts, UnitDeletionRequestService.ts, UnitRepository.ts |
| **Historial** | UnitEvent | StatusHistoryRepository.ts, logs.ts |
| **Notificaciones** | Notification | NotificationService.ts, notificationHub.ts |
| **Proveedores** | Provider | ProviderService.ts, ProviderController.ts |
| **Dashboards** | Unit, UnitEvent, UnitDefect | DashboardController.ts |

---

## Notas Importantes

### Timezone
- Todas las fechas se almacenan en UTC
- Conversión a `America/Mexico_City` en queries cuando se requiere
- Constante definida en `backend/src/constants/index.ts`

### Soft Delete
- **Unit.archivedAt**: Marca unidades como archivadas (soft delete)
- **Unit.archivedById**: Usuario responsable del archivado
- Queries regulares filtran `WHERE archivedAt IS NULL`

### Multi-tenancy
- Campo `plant` ('A1', 'A2') en User y Unit
- Los usuarios solo ven unidades de su planta
- Excepto roles ADMIN que ven todas

### Constraints Importantes
- **VIN único por planta**: Permite mismo VIN en diferentes plantas
- **Email único global**: Un usuario no puede tener duplicados
- **Proveedor único por nombre**: Evita duplicados

### Performance Tips
- Usar `findByStatusName()` en lugar de `findAll()` + filtro en memoria
- Limitar resultados con parámetro `limit`
- Incluir defectos solo cuando se necesiten mostrar
- Usar índices en WHERE clauses (plant, statusId, providerId)

---

## Actualizaciones y Mantenimiento

### Migraciones
- Archivo base: `docs/database-schema-postgresql.sql`
- Ejecutar en PostgreSQL para inicializar
- Para cambios, crear scripts de migración incrementales

### Seed Data
El esquema incluye datos iniciales:
- 7 Roles predefinidos
- 13 Estados de unidades
- 3 Grados de defectos (V1, V2, V3)
- 8+ Reparaciones estándar en catálogo

### Backup Recomendado
```bash
# Backup completo
pg_dump -h localhost -U usuario -d nissan_body > backup_$(date +%Y%m%d).sql

# Backup solo esquema
pg_dump -h localhost -U usuario -d nissan_body --schema-only > schema.sql

# Backup solo datos
pg_dump -h localhost -U usuario -d nissan_body --data-only > data.sql
```

---

## Contacto y Soporte

Para preguntas sobre el esquema o modificaciones:
1. Revisar este README
2. Consultar código en `backend/src/repositories/`
3. Verificar tipos en `backend/src/types/index.ts`

---

**Última actualización**: Marzo 2026  
**Versión del esquema**: 1.0  
**Base de datos**: PostgreSQL 14+
