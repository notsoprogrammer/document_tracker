-- Create documents table
CREATE TABLE IF NOT EXISTS documents (
    id SERIAL PRIMARY KEY,
    code TEXT UNIQUE NOT NULL,
    title TEXT NOT NULL,
    type TEXT NOT NULL,
    from_or_to TEXT NOT NULL,
    mode TEXT NOT NULL,
    assigned_to TEXT NOT NULL,
    file_path TEXT,
    file_name TEXT,
    remarks TEXT NOT NULL,
    person TEXT NOT NULL,
    incoming BOOLEAN NOT NULL,
    status TEXT NOT NULL DEFAULT 'Received',
    history TEXT NOT NULL DEFAULT '',
    image_urls TEXT,
    file_urls TEXT,
    file_names TEXT,
    local_image_paths TEXT,
    local_file_paths TEXT,
    needs_sync BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    compliance_deadline TIMESTAMP WITH TIME ZONE,
    scheduled_notification_ids TEXT,
    compliance_assignee TEXT,
    category TEXT,
    calendar_deadline TIMESTAMP WITH TIME ZONE,
    calendar_added BOOLEAN DEFAULT FALSE,
    attachments JSON
);

-- Create deleted_records table
CREATE TABLE IF NOT EXISTS deleted_records (
    id SERIAL PRIMARY KEY,
    deleted_by TEXT NOT NULL,
    doc_code TEXT NOT NULL,
    title TEXT NOT NULL,
    deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create device_tokens table
CREATE TABLE IF NOT EXISTS device_tokens (
    token TEXT PRIMARY KEY,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create notifications_history table
CREATE TABLE IF NOT EXISTS notifications_history (
    id SERIAL PRIMARY KEY,
    document_code TEXT NOT NULL,
    notification_type TEXT NOT NULL,
    notification_id INTEGER NOT NULL,
    scheduled_time TIMESTAMP WITH TIME ZONE NOT NULL,
    status TEXT NOT NULL DEFAULT 'scheduled',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    FOREIGN KEY (document_code) REFERENCES documents(code) ON DELETE CASCADE
);

-- Add foreign key constraint if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'fk_notifications_history_document_code'
        AND table_name = 'notifications_history'
    ) THEN
        ALTER TABLE notifications_history
        ADD CONSTRAINT fk_notifications_history_document_code
        FOREIGN KEY (document_code) REFERENCES documents(code) ON DELETE CASCADE;
    END IF;
END $$;

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_documents_code ON documents(code);
CREATE INDEX IF NOT EXISTS idx_documents_incoming ON documents(incoming);
CREATE INDEX IF NOT EXISTS idx_documents_status ON documents(status);
CREATE INDEX IF NOT EXISTS idx_deleted_records_doc_code ON deleted_records(doc_code);
CREATE INDEX IF NOT EXISTS idx_deleted_records_deleted_at ON deleted_records(deleted_at);
CREATE INDEX IF NOT EXISTS idx_notifications_history_document_code ON notifications_history(document_code);
CREATE INDEX IF NOT EXISTS idx_notifications_history_status ON notifications_history(status);
CREATE INDEX IF NOT EXISTS idx_notifications_history_created_at ON notifications_history(created_at);

-- Enable Row Level Security (RLS) if needed
-- ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE history_entries ENABLE ROW LEVEL SECURITY;

-- Create activities table
CREATE TABLE IF NOT EXISTS activities (
    id SERIAL PRIMARY KEY,
    title TEXT,
    start_time TIMESTAMP WITH TIME ZONE NOT NULL,
    end_time TIMESTAMP WITH TIME ZONE,
    people_involved TEXT NOT NULL,
    remarks TEXT NOT NULL,
    person TEXT NOT NULL,
    location TEXT,
    history JSON,
    status TEXT NOT NULL DEFAULT 'Scheduled',
    needs_sync BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for activities table
CREATE INDEX IF NOT EXISTS idx_activities_start_time ON activities(start_time);
CREATE INDEX IF NOT EXISTS idx_activities_status ON activities(status);

-- Create policies for RLS (uncomment and modify as needed)
-- CREATE POLICY "Enable all operations for authenticated users" ON documents
-- FOR ALL USING (auth.role() = 'authenticated');

-- CREATE POLICY "Enable all operations for authenticated users" ON history_entries
-- FOR ALL USING (auth.role() = 'authenticated');

-- CREATE POLICY "Enable all operations for authenticated users" ON activities
-- FOR ALL USING (auth.role() = 'authenticated');
