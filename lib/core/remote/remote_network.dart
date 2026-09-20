import 'dart:io';

/// A candidate address with the interface name retained for honest QR copy.
class RemoteNetworkAddress {
  const RemoteNetworkAddress({
    required this.address,
    required this.interfaceName,
    required this.rank,
  });

  final InternetAddress address;
  final String interfaceName;
  final int rank;

  String get host => address.address;
}

const List<String> remoteVirtualAdapterWords = <String>[
  'virtual',
  'vethernet',
  'hyper-v',
  'vmware',
  'virtualbox',
  'loopback',
  'bluetooth',
  'wsl',
  'docker',
  'tailscale',
  'zerotier',
  'radmin',
];

bool isPrivateRemoteIpv4(String value) {
  final List<int>? octets = _octets(value);
  if (octets == null) return false;
  if (octets[0] == 10) return true;
  if (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) return true;
  if (octets[0] == 192 && octets[1] == 168) return true;
  return false;
}

bool isLoopbackRemoteIpv4(String value) {
  final List<int>? octets = _octets(value);
  return octets != null && octets[0] == 127;
}

bool isVirtualAdapterName(String name) {
  final String lower = name.toLowerCase();
  return remoteVirtualAdapterWords.any(lower.contains);
}

/// Pure filtering/ranking step. It accepts plain candidates so it is easy to
/// test without touching the machine's actual adapters.
List<RemoteNetworkAddress> filterAndRankRemoteAddresses(
  Iterable<RemoteNetworkAddress> candidates, {
  bool allowLoopback = false,
}) {
  final List<RemoteNetworkAddress> private = candidates
      .where((RemoteNetworkAddress item) =>
          isPrivateRemoteIpv4(item.host) &&
          (allowLoopback || !isLoopbackRemoteIpv4(item.host)) &&
          !isVirtualAdapterName(item.interfaceName))
      .toList();
  if (private.isEmpty) {
    return candidates
        .where((RemoteNetworkAddress item) =>
            isPrivateRemoteIpv4(item.host) &&
            (allowLoopback || !isLoopbackRemoteIpv4(item.host)))
        .toList()
      ..sort(_compareNetworkAddress);
  }
  private.sort(_compareNetworkAddress);
  return private;
}

int remoteAdapterRank(String name) {
  final String lower = name.toLowerCase();
  if (lower.contains('wi-fi') ||
      lower.contains('wifi') ||
      lower.contains('wireless')) {
    return 0;
  }
  if (lower.contains('ethernet')) return 1;
  return 2;
}

int _compareNetworkAddress(RemoteNetworkAddress a, RemoteNetworkAddress b) {
  final int rank = a.rank.compareTo(b.rank);
  if (rank != 0) return rank;
  return a.host.compareTo(b.host);
}

/// Enumerates the currently available IPv4 candidates. The policy itself is
/// pure above; this small adapter is the only platform I/O in this file.
Future<List<RemoteNetworkAddress>> enumerateRemoteAddresses() async {
  try {
    final List<NetworkInterface> interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: true,
    );
    final List<RemoteNetworkAddress> candidates = <RemoteNetworkAddress>[];
    for (final NetworkInterface network in interfaces) {
      final int rank = remoteAdapterRank(network.name);
      for (final InternetAddress address in network.addresses) {
        candidates.add(RemoteNetworkAddress(
          address: address,
          interfaceName: network.name,
          rank: rank,
        ));
      }
    }
    return filterAndRankRemoteAddresses(candidates);
  } catch (_) {
    return const <RemoteNetworkAddress>[];
  }
}

List<int>? _octets(String value) {
  final List<String> parts = value.split('.');
  if (parts.length != 4) return null;
  final List<int> out = <int>[];
  for (final String part in parts) {
    final int? number = int.tryParse(part);
    if (number == null || number < 0 || number > 255) return null;
    out.add(number);
  }
  return out;
}
