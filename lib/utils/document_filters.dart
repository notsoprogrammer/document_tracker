/// Which documents belong to the Incoming and Outgoing folders.
///
/// These predicates exist so the home screen's folder counts and the folder
/// screens' lists cannot disagree. They previously each carried their own copy
/// of the rule and had drifted apart: the counts tested the `incoming` boolean
/// while the lists tested `flowStage`, so moving a document between folders
/// (which only writes `flow_stage`) never moved its count.
library;

import '../models/document.dart';

/// Modes that have a folder of their own on the home screen. Their documents
/// are listed there and must not also appear under Outgoing.
const Set<String> ownFolderModes = {
  'Flag Ceremony',
  'Office Function MOVs',
  'Locational & Zoning',
  'SP Documents',
  'Reclassification',
  'CDC Documents',
  'Resolutions',
};

/// True for documents the Incoming folder lists. Modes with a folder of their
/// own are excluded: a CDC or Resolutions document belongs in its own folder,
/// which is also where searching for it navigates ([_getFolderName]).
bool isIncomingDocument(Document d) =>
    d.flowStage == 'incoming' && !ownFolderModes.contains(d.mode);

/// True for documents the Outgoing folder lists. `circulated` is included:
/// a document forwarded a second time is still an outgoing record.
bool isOutgoingDocument(Document d) =>
    (d.flowStage == 'outgoing' || d.flowStage == 'circulated') &&
    !ownFolderModes.contains(d.mode);
