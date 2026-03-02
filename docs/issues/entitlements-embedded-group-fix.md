# Entitlements 401 - embedded_group Fix

## Root Cause
OSDU core-plus Entitlements uses a SQL query that joins `group` with
`embedded_group` via CROSS JOIN to resolve user group memberships.
The query parameter is the user's email (e.g. `test@osdu.osdu.local`),
which must exist as a row in the `group` table, linked via `embedded_group`
to every group the user belongs to.

During initial bootstrap, `POST /groups/.../members` failed with 500
("column reference 'id' is ambiguous") because `embedded_group` had a
surrogate `id` column conflicting with the recursive CTE. This prevented
the creation of:
- Member group row in `group` table
- `embedded_group` parent→child links

## Fixes Applied
1. Dropped surrogate `id` from `embedded_group`, set composite PK (parent_id, child_id)
2. Manually created member groups + embedded_group links for existing users
3. Set `GROUP_ID=osdu.local` (domain validation fix)

## If Re-bootstrapping
After creating partition + groups + adding members, run:
```sql
-- For each user email (e.g. test@osdu.osdu.local):
INSERT INTO "group" (name, email, description, partition_id)
VALUES ('<username>', '<user_email>', 'Member group', '<partition>')
ON CONFLICT (email) DO NOTHING;

INSERT INTO embedded_group (parent_id, child_id)
SELECT g.id, mg.id
FROM "group" mg
CROSS JOIN (
  SELECT g.id FROM member m
  JOIN member_to_group mtg ON m.id = mtg.member_id
  JOIN "group" g ON mtg.group_id = g.id
  WHERE m.email = '<user_email>'
) g
WHERE mg.email = '<user_email>'
ON CONFLICT (parent_id, child_id) DO NOTHING;
```
