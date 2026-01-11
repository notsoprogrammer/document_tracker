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
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create history_entries table
CREATE TABLE IF NOT EXISTS history_entries (
    id SERIAL PRIMARY KEY,
    document_code TEXT NOT NULL,
    action TEXT NOT NULL,
    person TEXT NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Add foreign key constraint after table creation (optional)
-- ALTER TABLE history_entries ADD CONSTRAINT fk_history_document_code
-- FOREIGN KEY (document_code) REFERENCES documents(code) ON DELETE CASCADE;

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_documents_code ON documents(code);
CREATE INDEX IF NOT EXISTS idx_documents_incoming ON documents(incoming);
CREATE INDEX IF NOT EXISTS idx_documents_status ON documents(status);
CREATE INDEX IF NOT EXISTS idx_history_entries_document_code ON history_entries(document_code);
CREATE INDEX IF NOT EXISTS idx_history_entries_timestamp ON history_entries(timestamp);

-- Enable Row Level Security (RLS) if needed
-- ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE history_entries ENABLE ROW LEVEL SECURITY;

-- Create policies for RLS (uncomment and modify as needed)
-- CREATE POLICY "Enable all operations for authenticated users" ON documents
-- FOR ALL USING (auth.role() = 'authenticated');

-- CREATE POLICY "Enable all operations for authenticated users" ON history_entries
-- FOR ALL USING (auth.role() = 'authenticated');
