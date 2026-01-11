-- Entitlements Database Schema
-- Required for OSDU Core Plus Entitlements service

-- member table
CREATE TABLE IF NOT EXISTS member (
    id BIGSERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    partition_id VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- group table (quoted because "group" is reserved keyword)
CREATE TABLE IF NOT EXISTS "group" (
    id BIGSERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    partition_id VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255)
);

-- member_to_group junction table
CREATE TABLE IF NOT EXISTS member_to_group (
    id BIGSERIAL PRIMARY KEY,
    member_id BIGINT NOT NULL REFERENCES member(id) ON DELETE CASCADE,
    group_id BIGINT NOT NULL REFERENCES "group"(id) ON DELETE CASCADE,
    role VARCHAR(50) DEFAULT 'MEMBER',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(member_id, group_id)
);

-- embedded_group for group hierarchy
CREATE TABLE IF NOT EXISTS embedded_group (
    id BIGSERIAL PRIMARY KEY,
    parent_id BIGINT NOT NULL REFERENCES "group"(id) ON DELETE CASCADE,
    child_id BIGINT NOT NULL REFERENCES "group"(id) ON DELETE CASCADE,
    UNIQUE(parent_id, child_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_member_email ON member(email);
CREATE INDEX IF NOT EXISTS idx_member_partition ON member(partition_id);
CREATE INDEX IF NOT EXISTS idx_group_email ON "group"(email);
CREATE INDEX IF NOT EXISTS idx_group_partition ON "group"(partition_id);
CREATE INDEX IF NOT EXISTS idx_m2g_member ON member_to_group(member_id);
CREATE INDEX IF NOT EXISTS idx_m2g_group ON member_to_group(group_id);
CREATE INDEX IF NOT EXISTS idx_embedded_parent ON embedded_group(parent_id);
CREATE INDEX IF NOT EXISTS idx_embedded_child ON embedded_group(child_id);
