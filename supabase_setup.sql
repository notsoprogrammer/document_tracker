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
    remarks TEXT NOT NULL,
    person TEXT NOT NULL,
    incoming BOOLEAN NOT NULL,
    status TEXT NOT NULL DEFAULT 'Received',
    history TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    compliance_deadline TIMESTAMP WITH TIME ZONE,
    scheduled_notification_ids TEXT
);

-- Create deleted_records table
CREATE TABLE IF NOT EXISTS deleted_records (
    id SERIAL PRIMARY KEY,
    deleted_by TEXT NOT NULL,
    doc_code TEXT NOT NULL,
    title TEXT NOT NULL,
    deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_documents_code ON documents(code);
CREATE INDEX IF NOT EXISTS idx_documents_incoming ON documents(incoming);
CREATE INDEX IF NOT EXISTS idx_documents_status ON documents(status);
CREATE INDEX IF NOT EXISTS idx_deleted_records_doc_code ON deleted_records(doc_code);
CREATE INDEX IF NOT EXISTS idx_deleted_records_deleted_at ON deleted_records(deleted_at);

-- Enable Row Level Security (RLS) if needed
-- ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE history_entries ENABLE ROW LEVEL SECURITY;

-- Create policies for RLS (uncomment and modify as needed)
-- CREATE POLICY "Enable all operations for authenticated users" ON documents
-- FOR ALL USING (auth.role() = 'authenticated');

-- CREATE POLICY "Enable all operations for authenticated users" ON history_entries
-- FOR ALL USING (auth.role() = 'authenticated');
