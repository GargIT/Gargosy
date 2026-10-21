import '../core/romm/romm_models.dart';
import '../emulators/bios_links.dart';

/// One of RomM's firmware files for a platform, and whether this PC has it.
class FirmwareStatus {
  const FirmwareStatus(this.firmware, {required this.onThisPc});
  final Firmware firmware;
  final bool onThisPc;
}

/// [firmware] (a platform's, from RomM) against the shared `bios\` ([files]):
/// a file is on this PC when one of its name is there, at any depth (an
/// emulator's subfolder too), in any case. Sorted by name.
List<FirmwareStatus> firmwareOnThisPc(List<Firmware> firmware, BiosFiles files, {String? platformSlug}) {
  final list = [
    for (final f in firmware) FirmwareStatus(f, onThisPc: files.find([f.fileName], platforms: [?platformSlug]) != null),
  ];
  list.sort((a, b) => a.firmware.fileName.toLowerCase().compareTo(b.firmware.fileName.toLowerCase()));
  return list;
}
