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
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_documents_code ON documents(code);
CREATE INDEX IF NOT EXISTS idx_documents_incoming ON documents(incoming);
CREATE INDEX IF NOT EXISTS idx_documents_status ON documents(status);

-- Enable Row Level Security (RLS) if needed
-- ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE history_entries ENABLE ROW LEVEL SECURITY;

-- Create policies for RLS (uncomment and modify as needed)
-- CREATE POLICY "Enable all operations for authenticated users" ON documents
-- FOR ALL USING (auth.role() = 'authenticated');

-- CREATE POLICY "Enable all operations for authenticated users" ON history_entries
-- FOR ALL USING (auth.role() = 'authenticated');
