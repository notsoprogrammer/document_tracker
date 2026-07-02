// Centralized constants for document types and abbreviations
const Map<String, String> typeMapping = {
  // Main types
  'Action Slip': 'AS',
  'Endorsement': 'END',
  'Executive Order': 'EO',
  'Letter': 'LET',
  'Leave': 'LV',
  'Memo': 'MEMO',
  'Report': 'REP',
  'Resolution': 'RES',
  'Request': 'REQ',
  'Ordinance': 'ORD',
  'Travel': 'TRV',
  'Transmittal': 'TRN',
  'Voucher/OBR': 'VOBR',
  'Others': 'OTH',

  // Other document types
  'AIP': 'AIP',
  'Annual Accomplishment Report': 'AAR',
  'Annual Budget': 'AB',
  'Barangay – AIP': 'BAIP',
  'Barangay – GAD': 'BGAD',
  'Cash Advance': 'CA',
  'CDC – Attendance': 'CDCA',
  'CDC – Minutes': 'CDCM',
  'CDC – Resolution': 'CDCRES',
  'Certificate/Attendance': 'CERT',
  'Clean-up Drives': 'CUD',
  'CLUP Zoning Reclassification': 'CLUPZ',
  'Execom Resolution': 'EXRES',
  'Supplemental AIP': 'SAIP',
  'CDC Invitation': 'CDCI',
  'SP Resolution': 'SPRES',
  'SP Ordinance': 'SPORD',
  'CSOs': 'CSO',
  'Dept. Heads Meeting': 'DHM',
  'DTR': 'DTR',
  'Earthquake Drills': 'EQD',
  'Flag Lowering': 'FL',
  'Flag Raising': 'FR',
  'Ecological Profile': 'ECO',
  'L&D/IDP/DNA': 'LID',
  'Liquidation/Reimbursement': 'LIQ',
  'Locational Clearance': 'LOC',
  'Man. Com': 'MC',
  'Monthly Accomplishment Report': 'MAR',
  'Monthly Staff Meeting': 'MSM',
  'OPCR': 'OPCR',
  'PFMAR/PFMIP': 'PFM',
  'PR/PPMP': 'PRP',
  'Quarterly Accomplishment Report': 'QAR',
  'Research/Studies/Trainings': 'RST',
  'Sectoral Plans': 'SP',
  'Tree Planting': 'TP',
  'Zoning Certification': 'ZCERT',
  'Zoning Clearance': 'ZC',
};

const List<String> documentTypes = [
  'Endorsement',
  'Executive Order',
  'Letter',
  'Leave',
  'Memo',
  'Report',
  'Resolution',
  'Request',
  'Ordinance',
  'Travel',
  'Transmittal',
  'Voucher/OBR',
  'Others'
];

const List<String> otherDocumentTypes = [
  "AIP",
  "Annual Accomplishment Report",
  "Annual Budget",
  "Barangay – AIP",
  "Barangay – GAD",
  "Cash Advance",
  "CDC – Attendance",
  "CDC – Minutes",
  "CDC – Resolution",
  "Certificate/Attendance",
  "Clean-up Drives",
  "CLUP Zoning Reclassification",
  "CSOs",
  "Dept. Heads Meeting",
  "DTR",
  "Earthquake Drills",
  "Ecological Profile",
  "L&D/IDP/DNA",
  "Liquidation/Reimbursement",
  "Locational Clearance",
  "Man. Com",
  "Monthly Accomplishment Report",
  "Monthly Staff Meeting",
  "OPCR",
  "PFMAR/PFMIP",
  "PR/PPMP",
  "Quarterly Accomplishment Report",
  "Research/Studies/Trainings",
  "Sectoral Plans",
  "Tree Planting",
  "Zoning Certification",
  "Zoning Clearance"
];

const List<String> locationalZoningTypes = [
  'Locational Clearance',
  'Zoning Clearance',
  'Zoning Certification',
];

const List<String> cdcTypes = [
  'CDC – Attendance',
  'CDC – Minutes',
  'CDC – Resolution',
  'Execom Resolution',
  'Supplemental AIP',
  'CDC Invitation',
];

const List<String> spDocumentTypes = [
  'SP Resolution',
  'SP Ordinance',
];

const List<String> reclassificationTypes = [
  'CLUP Zoning Reclassification',
];

const List<String> coreFunctions = [
  'AIP',
  'Barangay – AIP',
  'Barangay – GAD',
  'CDC – Attendance',
  'CDC – Minutes',
  'CDC – Resolution',
  'CLUP Zoning Reclassification',
  'CSOs',
  'Ecological Profile',
  'Locational Clearance',
  'Research/Studies/Trainings',
  'Sectoral Plans',
  'Zoning Certification',
  'Zoning Clearance',
];

const List<String> strategicFunctions = [
  'Liquidation/ Reimbursement',
  'PFMAR/PFMIP',
  'PR/PPMP',
];

const List<String> supportFunctions = [
  'Annual Accomplishment Report',
  'Annual Budget',
  'Cash Advance',
  'Certificate/Attendance',
  'Clean-up Drives',
  'Dept. Heads Meeting',
  'DTR',
  'Earthquake Drills',
  'Flag Lowering',
  'Flag Raising',
  'L&D/IDP/DNA',
  'Man. Com',
  'Monthly Accomplishment Report',
  'Monthly Staff Meeting',
  'OPCR',
  'Quarterly Accomplishment Report',
  'Tree Planting',
  'Others',
];

const List<String> resolutionTypes = [
  'CDC – Resolution',
  'Execom Resolution',
  'Resolution',
  'SP Ordinance',
  'SP Resolution',
];
