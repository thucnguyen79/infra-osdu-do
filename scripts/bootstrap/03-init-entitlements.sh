#!/bin/bash
# 03-init-entitlements.sh - Bootstrap entitlements groups and users
# Usage: ./03-init-entitlements.sh [USER_EMAIL] [PARTITION_NAME]

set -e

USER_EMAIL="${1:-test@osdu.internal}"
PARTITION_NAME="${2:-osdu}"
TOOLBOX_POD="deploy/osdu-toolbox"
NAMESPACE="osdu-core"
PG_HOST="osdu-postgres.osdu-data.svc.cluster.local"
PG_USER="osduadmin"
PG_PASS="CHANGE_ME_STRONG"

echo "=== Bootstrapping Entitlements for user: $USER_EMAIL, partition: $PARTITION_NAME ==="

kubectl -n $NAMESPACE exec -it $TOOLBOX_POD -- bash -c "
PGPASSWORD=$PG_PASS psql -h $PG_HOST -U $PG_USER -d entitlements << 'EOF'
-- Insert user
INSERT INTO member (email, partition_id) 
VALUES ('$USER_EMAIL', '$PARTITION_NAME')
ON CONFLICT (email) DO NOTHING;

-- Insert essential groups
INSERT INTO \"group\" (email, name, description, partition_id) VALUES
('users@$PARTITION_NAME.$PARTITION_NAME.local', 'users', 'All users', '$PARTITION_NAME'),
('users.datalake.ops@$PARTITION_NAME.$PARTITION_NAME.local', 'users.datalake.ops', 'OSDU Operators', '$PARTITION_NAME'),
('users.datalake.admins@$PARTITION_NAME.$PARTITION_NAME.local', 'users.datalake.admins', 'OSDU Admins', '$PARTITION_NAME'),
('users.datalake.viewers@$PARTITION_NAME.$PARTITION_NAME.local', 'users.datalake.viewers', 'OSDU Viewers', '$PARTITION_NAME'),
('users.datalake.editors@$PARTITION_NAME.$PARTITION_NAME.local', 'users.datalake.editors', 'OSDU Editors', '$PARTITION_NAME'),
('service.entitlements.user@$PARTITION_NAME.$PARTITION_NAME.local', 'service.entitlements.user', 'Entitlements Service', '$PARTITION_NAME'),
('service.legal.user@$PARTITION_NAME.$PARTITION_NAME.local', 'service.legal.user', 'Legal Service User', '$PARTITION_NAME'),
('service.legal.admin@$PARTITION_NAME.$PARTITION_NAME.local', 'service.legal.admin', 'Legal Service Admin', '$PARTITION_NAME'),
('service.legal.editor@$PARTITION_NAME.$PARTITION_NAME.local', 'service.legal.editor', 'Legal Service Editor', '$PARTITION_NAME'),
('service.storage.user@$PARTITION_NAME.$PARTITION_NAME.local', 'service.storage.user', 'Storage Service User', '$PARTITION_NAME'),
('service.storage.admin@$PARTITION_NAME.$PARTITION_NAME.local', 'service.storage.admin', 'Storage Service Admin', '$PARTITION_NAME'),
('service.schema-service.user@$PARTITION_NAME.$PARTITION_NAME.local', 'service.schema-service.user', 'Schema Service User', '$PARTITION_NAME'),
('service.schema-service.admin@$PARTITION_NAME.$PARTITION_NAME.local', 'service.schema-service.admin', 'Schema Service Admin', '$PARTITION_NAME')
ON CONFLICT (email) DO NOTHING;

-- Add user to all groups
INSERT INTO member_to_group (member_id, group_id, role)
SELECT m.id, g.id, 'OWNER'
FROM member m, \"group\" g
WHERE m.email = '$USER_EMAIL' 
AND g.partition_id = '$PARTITION_NAME'
ON CONFLICT (member_id, group_id) DO NOTHING;

SELECT 'User ' || '$USER_EMAIL' || ' added to ' || count(*) || ' groups' FROM member_to_group 
WHERE member_id = (SELECT id FROM member WHERE email = '$USER_EMAIL');
EOF
"

echo "=== Entitlements bootstrap completed ==="
