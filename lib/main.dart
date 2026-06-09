// main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:http/http.dart' as http;
import 'package:webthree/webthree.dart';
import 'package:webthree/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart' as hash_lib;
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'dart:js_util' as js_util;

// ==============================================================
// 1. STRICT JS INTEROP (Multi-Wallet & EVM Bridge)
// ==============================================================
@JS('window.ethereum')
external Ethereum? get ethereum;

@JS('window.coinbaseWalletExtension')
external Ethereum? get coinbaseWalletExtension;

@JS('window.trustwallet')
external Ethereum? get trustWallet;

@JS('window.phantom.ethereum')
external Ethereum? get phantomWallet;

@JS()
extension type Ethereum._(JSObject _) implements JSObject {
  external JSPromise request(RequestArguments args);
  external bool? get isMetaMask;
  external bool? get isRabby;
  external bool? get isCoinbaseWallet;
  external bool? get isTrust;
  external bool? get isPhantom;
  external bool? get isMiniPay;
}

@JS()
@anonymous
extension type RequestArguments._(JSObject _) implements JSObject {
  external factory RequestArguments({
    required JSString method,
    JSAny? params,
  });
}

bool isMiniPay() {
  try {
    return ethereum?.isMiniPay == true;
  } catch (e) {
    return false;
  }
}

Map<String, String> parseWebUrlParams() {
  final url = web.window.location.href;
  final uri = Uri.parse(url);
  final params = <String, String>{};
  
  params.addAll(uri.queryParameters);
  
  if (uri.hasFragment && uri.fragment.contains('?')) {
    final fragmentQuery = uri.fragment.substring(uri.fragment.indexOf('?') + 1);
    params.addAll(Uri.splitQueryString(fragmentQuery));
  }
  return params;
}

// ==============================================================
// KEYBOARD SCROLL WRAPPER (FIXED FOR TEXT INPUTS)
// ==============================================================
class KeyboardScrollWrapper extends StatefulWidget {
  final Widget child;
  final ScrollController controller;
  const KeyboardScrollWrapper({super.key, required this.child, required this.controller});
  @override State<KeyboardScrollWrapper> createState() => _KeyboardScrollWrapperState();
}

class _KeyboardScrollWrapperState extends State<KeyboardScrollWrapper> {
  final FocusNode _focusNode = FocusNode();
  @override void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) { _focusNode.requestFocus(); }); }
  @override void dispose() { _focusNode.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        if (FocusManager.instance.primaryFocus == null || FocusManager.instance.primaryFocus == FocusManager.instance.rootScope) {
          _focusNode.requestFocus();
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          FocusManager.instance.primaryFocus?.unfocus();
          _focusNode.requestFocus();
        },
        child: Focus(
          focusNode: _focusNode, 
          autofocus: true, 
          canRequestFocus: true,
          onKeyEvent: (node, event) {
            if (FocusManager.instance.primaryFocus != _focusNode) return KeyEventResult.ignored;

            if (event is KeyDownEvent || event is KeyRepeatEvent) {
              const double scrollAmount = 150.0; 
              const double pageScrollAmount = 400.0;
              double target = widget.controller.offset;
              
              if (event.logicalKey == LogicalKeyboardKey.arrowDown) target += scrollAmount;
              else if (event.logicalKey == LogicalKeyboardKey.arrowUp) target -= scrollAmount;
              else if (event.logicalKey == LogicalKeyboardKey.pageDown || event.logicalKey == LogicalKeyboardKey.space) target += pageScrollAmount;
              else if (event.logicalKey == LogicalKeyboardKey.pageUp) target -= pageScrollAmount;
              else return KeyEventResult.ignored;

              if (target != widget.controller.offset) {
                target = target.clamp(0.0, widget.controller.position.maxScrollExtent);
                widget.controller.animateTo(target, duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: widget.child,
        ),
      ),
    );
  }
}

// ==============================================================
// LIVE COUNTDOWN TIMER WIDGET
// ==============================================================
class LiveTimer extends StatefulWidget {
  final int unlockTimeEpoch;
  final VoidCallback? onExpire;
  final Widget Function(String days, String hrs, String mins, String secs, bool isExpired) builder;
  const LiveTimer({super.key, required this.unlockTimeEpoch, required this.builder, this.onExpire});
  @override State<LiveTimer> createState() => _LiveTimerState();
}

class _LiveTimerState extends State<LiveTimer> {
  Timer? _timer;
  late DateTime _unlockTime;
  Duration _timeLeft = Duration.zero;
  bool _hasFired = false;

  @override
  void initState() {
    super.initState();
    _unlockTime = DateTime.fromMillisecondsSinceEpoch(widget.unlockTimeEpoch * 1000);
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  void _updateTime() {
    final diff = _unlockTime.difference(DateTime.now());
    if (diff.isNegative) {
      _timer?.cancel();
      if (mounted) setState(() => _timeLeft = Duration.zero);
      if (!_hasFired && widget.onExpire != null) {
        _hasFired = true;
        widget.onExpire!();
      }
    } else {
      if (mounted) setState(() => _timeLeft = diff);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isExpired = _unlockTime.isBefore(DateTime.now());
    final days = isExpired ? "00" : _timeLeft.inDays.toString().padLeft(2, '0');
    final hrs = isExpired ? "00" : (_timeLeft.inHours % 24).toString().padLeft(2, '0');
    final mins = isExpired ? "00" : (_timeLeft.inMinutes % 60).toString().padLeft(2, '0');
    final secs = isExpired ? "00" : (_timeLeft.inSeconds % 60).toString().padLeft(2, '0');
    return widget.builder(days, hrs, mins, secs, isExpired);
  }
}

// ==============================================================
// 2. CONSTANTS, EMAIL & ENCRYPTION SERVICES
// ==============================================================
class AppConstants {
  static const String appSecret = "LIFELINE_CELO_HACKATHON_2026_SECRET_KEY";
  static const String rpcUrl = "https://celo-mainnet.g.alchemy.com/v2/iC-kygJ7M4B-sdyiSfBup";
  static const int chainId = 42220; 
  
  static const String lifeLineContract = "0x4ceb4f21b69cba6c67c03f17c56a5c42e51b4bc1"; 
  
  static final Map<String, Map<String, dynamic>> tokens = {
    'CELO': {'address': '0x471EcE3750Da237f93B8E339c536989b8978a438', 'decimals': 18},
    'USDC': {'address': '0xcebA9300f2b948710d2653dD7B07f33A8B32118C', 'decimals': 6},
  };

  static const String emailServiceId = "service_vn7cori";
  static const String emailTemplateId = "template_rq9b5e6";
  static const String emailPublicKey = "Lq6_Q8yKgmRsCIL-m";
}

class EmailService {
  static final String _url = 'https://api.emailjs.com/api/v1.0/email/send';

  static Future<bool> sendInheritanceEmail({
    required String heirName, required String heirEmail, required String ownerName,
    required String message, required String claimUrl, required String amount, required String tokenSymbol,
  }) async {
    try {
      debugPrint('🔥 TRACE: Sending EmailJS payload to $heirEmail...');
      final response = await http.post(
        Uri.parse(_url),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json', 'origin': 'http://localhost'},
        body: json.encode({
          'service_id': AppConstants.emailServiceId,
          'template_id': AppConstants.emailTemplateId,
          'user_id': AppConstants.emailPublicKey,
          'template_params': {
            'to_name': heirName, 'to_email': heirEmail, 'from_name': ownerName,
            'message': message, 'claim_url': claimUrl, 'amount': amount, 'token_symbol': tokenSymbol,
          }
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('🔥 TRACE: ❌ Email Error: $e');
      return false;
    }
  }
}

class EvmEncryptionService {
  static Map<String, String> generateEphemeralKeyPair() {
    final rng = Random.secure();
    final privateKey = EthPrivateKey.createRandom(rng);
    return {
      'privateKey': crypto.bytesToHex(privateKey.privateKey, include0x: true),
      'address': privateKey.address.hexEip55.toLowerCase(),
    };
  }

  static String encryptWithPin(String plainText, String pin) {
    final secretRaw = pin + AppConstants.appSecret;
    final keyBytes = hash_lib.sha256.convert(utf8.encode(secretRaw)).bytes;
    final key = encrypt.Key(Uint8List.fromList(keyBytes));
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return '${iv.base64}:${encrypted.base64}'; 
  }

  static String decryptWithPin(String encryptedPayload, String pin) {
    try {
      final parts = encryptedPayload.split(':');
      final iv = encrypt.IV.fromBase64(parts[0]);
      final cipherText = parts[1];
      final secretRaw = pin + AppConstants.appSecret;
      final keyBytes = hash_lib.sha256.convert(utf8.encode(secretRaw)).bytes;
      final key = encrypt.Key(Uint8List.fromList(keyBytes));
      final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
      return encrypter.decrypt(encrypt.Encrypted.fromBase64(cipherText), iv: iv);
    } catch (e) {
      throw Exception("INVALID_PIN");
    }
  }
}

// ==============================================================
// 3. STATE & TRANSACTION MANAGER 
// ==============================================================
class CeloWalletProvider extends ChangeNotifier {
  String? userAddress;
  Ethereum? activeProvider; 
  
  Map<String, double> tokenBalances = {'CELO': 0.0, 'USDC': 0.0};
  List<Map<String, dynamic>> activeVaults = [];
  
  bool isConnected = false;
  bool isLoading = false;
  
  bool isSyncingBalances = false; 
  bool isSyncingVaults = false; 
  
  String? errorMessage;
  String loadingStatus = "";

  final Web3Client _web3client = Web3Client(AppConstants.rpcUrl, http.Client());

  final String _erc20Abi = '[{"constant":true,"inputs":[{"name":"_owner","type":"address"}],"name":"balanceOf","outputs":[{"name":"balance","type":"uint256"}],"type":"function"}, {"constant":false,"inputs":[{"name":"_spender","type":"address"},{"name":"_value","type":"uint256"}],"name":"approve","outputs":[{"name":"","type":"bool"}],"type":"function"}, {"constant":false,"inputs":[{"name":"_to","type":"address"},{"name":"_value","type":"uint256"}],"name":"transfer","outputs":[{"name":"","type":"bool"}],"type":"function"}]';
  final String _lifeLineAbi = '[{"inputs":[{"internalType":"address","name":"tokenAddress","type":"address"},{"internalType":"address","name":"heirAddress","type":"address"},{"internalType":"bytes32","name":"heirPubkey","type":"bytes32"},{"internalType":"uint256","name":"amount","type":"uint256"},{"internalType":"uint64","name":"inactivityDuration","type":"uint64"}],"name":"createVault","outputs":[{"internalType":"uint64","name":"","type":"uint64"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"vaultCounter","outputs":[{"internalType":"uint64","name":"","type":"uint64"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint64","name":"vaultId","type":"uint64"}],"name":"pingVault","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint64","name":"vaultId","type":"uint64"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"addFunds","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint64","name":"vaultId","type":"uint64"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"withdrawFunds","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint64","name":"vaultId","type":"uint64"}],"name":"cancelVault","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint64","name":"vaultId","type":"uint64"}],"name":"getVault","outputs":[{"components":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"address","name":"heirAddress","type":"address"},{"internalType":"bytes32","name":"heirPubkey","type":"bytes32"},{"internalType":"address","name":"token","type":"address"},{"internalType":"uint256","name":"balance","type":"uint256"},{"internalType":"uint64","name":"unlockTime","type":"uint64"},{"internalType":"uint64","name":"inactivityDuration","type":"uint64"},{"internalType":"bool","name":"isActive","type":"bool"}],"internalType":"struct LifeLine.Vault","name":"","type":"tuple"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint64","name":"vaultId","type":"uint64"},{"internalType":"bytes32","name":"sigR","type":"bytes32"},{"internalType":"bytes32","name":"sigS","type":"bytes32"},{"internalType":"uint8","name":"sigV","type":"uint8"}],"name":"claimInheritance","outputs":[],"stateMutability":"nonpayable","type":"function"}]';

  bool hasSufficientBalance(String symbol, double requiredAmount) {
    double buffer = symbol == 'CELO' ? 0.02 : 0.0;
    return (tokenBalances[symbol] ?? 0.0) >= (requiredAmount + buffer);
  }

  BigInt _parseAmountToWei(String amountStr, int decimals) {
    final parts = amountStr.split('.');
    String whole = parts[0];
    if (whole.isEmpty) whole = '0';
    String fraction = parts.length > 1 ? parts[1] : '';
    if (fraction.length > decimals) fraction = fraction.substring(0, decimals);
    fraction = fraction.padRight(decimals, '0');
    return BigInt.parse(whole + fraction);
  }

  Future<void> connectProvider(Ethereum? provider, BuildContext context) async {
    try {
      isLoading = true;
      errorMessage = null;
      loadingStatus = "Connecting Web3...";
      notifyListeners();

      if (provider == null) throw Exception("Wallet not detected. Please install the required extension or app.");

      final args = RequestArguments(method: 'eth_requestAccounts'.toJS);
      
      final result = await js_util.promiseToFuture(provider.request(args)).timeout(const Duration(seconds: 15), onTimeout: () {
        throw Exception("Wallet connection timed out. Please check your extension/app.");
      });
      
      final List<dynamic> accounts = result as List<dynamic>;
      if (accounts.isEmpty) throw Exception("Connection rejected by user.");
      
      userAddress = accounts.first.toString().toLowerCase();
      activeProvider = provider;
      isConnected = true;

      if (!isMiniPay()) {
        try {
          final switchArgs = RequestArguments(
            method: 'wallet_switchEthereumChain'.toJS,
            params: [{'chainId': '0x${AppConstants.chainId.toRadixString(16)}'}].jsify()
          );
          await js_util.promiseToFuture(provider.request(switchArgs)).timeout(const Duration(seconds: 3));
        } catch (e) {
          debugPrint('🔥 TRACE: Network Switch Bypassed/Failed: $e. Proceeding anyway.');
        } 
      }

      refreshBalances(); 
      
    } catch (e) {
      errorMessage = e.toString().replaceAll('Exception:', '').trim();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void disconnectWallet() {
    userAddress = null;
    activeProvider = null;
    isConnected = false;
    tokenBalances = {'CELO': 0.0, 'USDC': 0.0};
    activeVaults = [];
    errorMessage = null;
    notifyListeners();
  }

  void dismissVault(int vaultId) {
    if (userAddress == null) return;
    web.window.localStorage.setItem('ll_dismissed_${userAddress}_$vaultId', 'true');
    activeVaults.removeWhere((v) => v['id'] == vaultId);
    notifyListeners();
  }

  Future<void> refreshBalances() async {
    if (userAddress == null) return;
    try {
      isSyncingBalances = true; 
      notifyListeners();

      final address = EthereumAddress.fromHex(userAddress!, enforceEip55: false);
      
      final celoBal = await _web3client.getBalance(address).timeout(const Duration(seconds: 10));
      tokenBalances['CELO'] = celoBal.getValueInUnit(EtherUnit.ether);

      final usdcAddr = EthereumAddress.fromHex(AppConstants.tokens['USDC']!['address'], enforceEip55: false);
      final contract = DeployedContract(ContractAbi.fromJson(_erc20Abi, 'ERC20'), usdcAddr);
      final balanceOfFunc = contract.function('balanceOf');
      
      final usdcResponse = await _web3client.call(contract: contract, function: balanceOfFunc, params: [address])
        .timeout(const Duration(seconds: 10));
        
      if (usdcResponse.isNotEmpty) {
        final rawUsdc = usdcResponse.first as BigInt;
        final decimals = AppConstants.tokens['USDC']!['decimals'] as int;
        tokenBalances['USDC'] = rawUsdc / BigInt.from(pow(10, decimals));
      }

      if (!AppConstants.lifeLineContract.contains("CHANGE_THIS")) {
        fetchUserVaults(); 
      }
      
    } catch (e) {
      debugPrint('🔥 TRACE: refreshBalances() Sync failed or timed out: $e');
    } finally {
      isSyncingBalances = false; 
      notifyListeners();
    }
  }

  Future<void> fetchUserVaults() async {
    if (userAddress == null) return;
    try {
      isSyncingVaults = true;
      notifyListeners();

      final llContract = DeployedContract(ContractAbi.fromJson(_lifeLineAbi, 'LifeLine'), EthereumAddress.fromHex(AppConstants.lifeLineContract, enforceEip55: false));
      final counterFunc = llContract.function('vaultCounter');
      final getVaultFunc = llContract.function('getVault');
      
      final counterRes = await _web3client.call(contract: llContract, function: counterFunc, params: []).timeout(const Duration(seconds: 10));
      final totalVaults = (counterRes.first as BigInt).toInt();

      List<Map<String, dynamic>> fetchedVaults = [];
      
      const int chunkSize = 20; 
      for (int i = 1; i <= totalVaults; i += chunkSize) {
        final end = (i + chunkSize - 1 > totalVaults) ? totalVaults : i + chunkSize - 1;
        
        List<Future<void>> futures = [];
        for (int j = i; j <= end; j++) {
          futures.add(() async {
            try {
              final vaultRes = await _web3client.call(contract: llContract, function: getVaultFunc, params: [BigInt.from(j)]).timeout(const Duration(seconds: 8));
              final vaultData = vaultRes.first as List<dynamic>; 
              
              final owner = vaultData[0].toString().toLowerCase();
              final isActive = vaultData[7] as bool;

              final isDismissed = web.window.localStorage.getItem('ll_dismissed_${userAddress}_$j') == 'true';

              if (owner == userAddress && !isDismissed) {
                final tokenHex = vaultData[3].toString().toLowerCase();
                String symbol = "Unknown";
                int decimals = 18;
                
                if (tokenHex == AppConstants.tokens['USDC']!['address'].toLowerCase()) { symbol = "USDC"; decimals = 6; }
                else if (tokenHex == AppConstants.tokens['CELO']!['address'].toLowerCase()) { symbol = "CELO"; decimals = 18; }

                final rawBalance = vaultData[4] as BigInt;
                final formattedBalance = rawBalance / BigInt.from(pow(10, decimals));

                fetchedVaults.add({
                  'id': j,
                  'heir': vaultData[1].toString(),
                  'tokenSymbol': symbol,
                  'balance': formattedBalance,
                  'unlockTime': (vaultData[5] as BigInt).toInt(),
                  'duration': (vaultData[6] as BigInt).toInt(),
                  'isActive': isActive 
                });
              }
            } catch (e) {
              debugPrint('🔥 TRACE: Failed to fetch vault #$j: $e');
            }
          }());
        }
        
        await Future.wait(futures);
        await Future.delayed(const Duration(milliseconds: 300)); 
      }
      
      activeVaults = fetchedVaults;
      
    } catch (e) {
      debugPrint('🔥 TRACE: Failed global vault fetch: $e');
    } finally {
      isSyncingVaults = false;
      notifyListeners();
    }
  }

  Future<String> sendAndWait({required String to, required String data, String value = "0x0", required String actionName}) async {
    if (activeProvider == null) throw Exception("Wallet disconnected!");

    final txParams = {'to': to, 'from': userAddress, 'data': data, 'value': value};
    final args = RequestArguments(
      method: 'eth_sendTransaction'.toJS,
      params: [txParams].jsify()
    );
    
    final txHash = (await js_util.promiseToFuture(activeProvider!.request(args))).toString();
    debugPrint('🔥 TRACE: [$actionName] Mined to Mempool: $txHash');

    int attempts = 0;
    while (attempts < 30) {
      await Future.delayed(const Duration(seconds: 2));
      try {
        final receipt = await _web3client.getTransactionReceipt(txHash);
        if (receipt != null) {
          if (receipt.status == true) return txHash;
          else throw Exception("Transaction reverted by the smart contract.");
        }
      } catch (e) {
        if (e.toString().contains("reverted")) rethrow;
      }
      attempts++;
    }
    throw Exception("Transaction timed out.");
  }

  Future<bool> initializeVault({
    required String tokenSymbol, required String amountStr, required int durationSeconds,
    required bool isEmailMode, required String heirName,
    String? heirEmail, String? pin, String? directWalletAddress,
  }) async {
    try {
      if (AppConstants.lifeLineContract.contains("CHANGE_THIS")) throw Exception("Add Mainnet Contract Address to AppConstants!");

      isLoading = true;
      errorMessage = null;
      notifyListeners();

      final tokenAddr = AppConstants.tokens[tokenSymbol]!['address'];
      final decimals = AppConstants.tokens[tokenSymbol]!['decimals'] as int;
      final amountWei = _parseAmountToWei(amountStr, decimals);

      String targetAddress = "";
      String? encryptedPk;
      Map<String, String>? keys;

      if (isEmailMode) {
        keys = EvmEncryptionService.generateEphemeralKeyPair();
        encryptedPk = EvmEncryptionService.encryptWithPin(keys['privateKey']!, pin!);
        targetAddress = keys['address']!; 
      } else {
        targetAddress = directWalletAddress!.toLowerCase();
      }

      loadingStatus = isEmailMode ? "Step 1 of 3: Approving $tokenSymbol..." : "Step 1 of 2: Approving $tokenSymbol...";
      notifyListeners();
      final erc20Contract = DeployedContract(ContractAbi.fromJson(_erc20Abi, 'ERC20'), EthereumAddress.fromHex(tokenAddr, enforceEip55: false));
      final approveFunc = erc20Contract.function('approve');
      final approveData = crypto.bytesToHex(Transaction.callContract(
        contract: erc20Contract, function: approveFunc, 
        parameters: [EthereumAddress.fromHex(AppConstants.lifeLineContract, enforceEip55: false), amountWei]
      ).data!, include0x: true);
      
      await sendAndWait(to: tokenAddr, data: approveData, actionName: "ERC20 Approval");

      loadingStatus = isEmailMode ? "Step 2 of 3: Locking Vault On-Chain..." : "Step 2 of 2: Locking Vault On-Chain...";
      notifyListeners();
      final llContract = DeployedContract(ContractAbi.fromJson(_lifeLineAbi, 'LifeLine'), EthereumAddress.fromHex(AppConstants.lifeLineContract, enforceEip55: false));
      final counterFunc = llContract.function('vaultCounter');
      final counterRes = await _web3client.call(contract: llContract, function: counterFunc, params: []);
      final nextVaultId = (counterRes.first as BigInt).toInt() + 1;

      final createFunc = llContract.function('createVault');
      final createData = crypto.bytesToHex(Transaction.callContract(
        contract: llContract, function: createFunc,
        parameters: [
          EthereumAddress.fromHex(tokenAddr, enforceEip55: false),
          EthereumAddress.fromHex(targetAddress, enforceEip55: false),
          Uint8List.fromList(List.filled(32, 1)), 
          amountWei, BigInt.from(durationSeconds)
        ]
      ).data!, include0x: true);

      await sendAndWait(to: AppConstants.lifeLineContract, data: createData, actionName: "Create Vault");

      if (isEmailMode) {
        loadingStatus = "Step 3 of 3: Pre-funding Claim Link...";
        notifyListeners();
        await sendAndWait(to: targetAddress, data: "0x", value: "0x470DE4DF820000", actionName: "Gas Funding");

        final encodedPayload = Uri.encodeComponent(encryptedPk!);
        final claimUrl = "https://uselifelineprotocol.web.app/#/?vaultId=$nextVaultId&payload=$encodedPayload&token=$tokenAddr";
        
        web.window.localStorage.setItem('ll_claim_$nextVaultId', claimUrl);
        web.window.localStorage.setItem('ll_token_$nextVaultId', tokenSymbol);
        web.window.localStorage.setItem('ll_amount_$nextVaultId', amountStr);
        web.window.localStorage.setItem('ll_email_$nextVaultId', heirEmail!);
        web.window.localStorage.setItem('ll_name_$nextVaultId', heirName);
      }

      await refreshBalances();
      return true;

    } catch (e) {
      errorMessage = e.toString().replaceAll("Exception:", "").trim();
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> autoDispatchEmail(int vaultId, BuildContext context) async {
    final sent = web.window.localStorage.getItem('ll_sent_$vaultId');
    if (sent == 'true') return; 

    final claimUrl = web.window.localStorage.getItem('ll_claim_$vaultId');
    final email = web.window.localStorage.getItem('ll_email_$vaultId');
    final name = web.window.localStorage.getItem('ll_name_$vaultId');
    final amount = web.window.localStorage.getItem('ll_amount_$vaultId');
    final token = web.window.localStorage.getItem('ll_token_$vaultId');

    if (claimUrl != null && email != null) {
      debugPrint('🔥 TRACE: Auto-dispatching email for Vault #$vaultId');
      final success = await EmailService.sendInheritanceEmail(
        heirName: name ?? "Beneficiary", heirEmail: email, ownerName: "A User",
        message: "The inactivity timer has expired. Your inheritance is ready to be claimed.",
        claimUrl: claimUrl, amount: amount ?? "0", tokenSymbol: token ?? "USDC",
      );
      if (success) {
        web.window.localStorage.setItem('ll_sent_$vaultId', 'true');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Auto-dispatched claim email for Vault #$vaultId!"), backgroundColor: AppTheme.green));
        }
      }
    }
  }

  Future<bool> pingVault(int vaultId) async {
    try {
      isLoading = true;
      loadingStatus = "Pinging Vault...";
      notifyListeners();
      final llContract = DeployedContract(ContractAbi.fromJson(_lifeLineAbi, 'LifeLine'), EthereumAddress.fromHex(AppConstants.lifeLineContract, enforceEip55: false));
      final pingFunc = llContract.function('pingVault');
      final data = crypto.bytesToHex(Transaction.callContract(
        contract: llContract, function: pingFunc, parameters: [BigInt.from(vaultId)]
      ).data!, include0x: true);

      await sendAndWait(to: AppConstants.lifeLineContract, data: data, actionName: "Ping Vault");
      await fetchUserVaults();
      return true;
    } catch(e) {
      errorMessage = e.toString().replaceAll("Exception:", "").trim();
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addFunds(int vaultId, String tokenSymbol, String amountStr) async {
    try {
      isLoading = true;
      notifyListeners();

      final tokenAddr = AppConstants.tokens[tokenSymbol]!['address'];
      final decimals = AppConstants.tokens[tokenSymbol]!['decimals'] as int;
      final amountWei = _parseAmountToWei(amountStr, decimals);

      loadingStatus = "Approving funds...";
      notifyListeners();
      final erc20Contract = DeployedContract(ContractAbi.fromJson(_erc20Abi, 'ERC20'), EthereumAddress.fromHex(tokenAddr, enforceEip55: false));
      final approveFunc = erc20Contract.function('approve');
      final approveData = crypto.bytesToHex(Transaction.callContract(
        contract: erc20Contract, function: approveFunc, 
        parameters: [EthereumAddress.fromHex(AppConstants.lifeLineContract, enforceEip55: false), amountWei]
      ).data!, include0x: true);
      await sendAndWait(to: tokenAddr, data: approveData, actionName: "ERC20 Approval");

      loadingStatus = "Adding to Vault...";
      notifyListeners();
      final llContract = DeployedContract(ContractAbi.fromJson(_lifeLineAbi, 'LifeLine'), EthereumAddress.fromHex(AppConstants.lifeLineContract, enforceEip55: false));
      final addFundsFunc = llContract.function('addFunds');
      final data = crypto.bytesToHex(Transaction.callContract(
        contract: llContract, function: addFundsFunc, parameters: [BigInt.from(vaultId), amountWei]
      ).data!, include0x: true);

      await sendAndWait(to: AppConstants.lifeLineContract, data: data, actionName: "Add Funds");
      await refreshBalances();
      return true;
    } catch(e) {
      errorMessage = e.toString().replaceAll("Exception:", "").trim();
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> withdrawFunds(int vaultId, String tokenSymbol, String amountStr) async {
    try {
      isLoading = true;
      loadingStatus = "Withdrawing...";
      notifyListeners();
      
      final decimals = AppConstants.tokens[tokenSymbol]!['decimals'] as int;
      final amountWei = _parseAmountToWei(amountStr, decimals);

      final llContract = DeployedContract(ContractAbi.fromJson(_lifeLineAbi, 'LifeLine'), EthereumAddress.fromHex(AppConstants.lifeLineContract, enforceEip55: false));
      final withdrawFunc = llContract.function('withdrawFunds');
      final data = crypto.bytesToHex(Transaction.callContract(
        contract: llContract, function: withdrawFunc, parameters: [BigInt.from(vaultId), amountWei]
      ).data!, include0x: true);

      await sendAndWait(to: AppConstants.lifeLineContract, data: data, actionName: "Withdraw");
      await refreshBalances();
      return true;
    } catch(e) {
      errorMessage = e.toString().replaceAll("Exception:", "").trim();
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> cancelVault(int vaultId) async {
    try {
      isLoading = true;
      loadingStatus = "Cancelling Vault...";
      notifyListeners();

      final llContract = DeployedContract(ContractAbi.fromJson(_lifeLineAbi, 'LifeLine'), EthereumAddress.fromHex(AppConstants.lifeLineContract, enforceEip55: false));
      final cancelFunc = llContract.function('cancelVault');
      final data = crypto.bytesToHex(Transaction.callContract(
        contract: llContract, function: cancelFunc, parameters: [BigInt.from(vaultId)]
      ).data!, include0x: true);

      await sendAndWait(to: AppConstants.lifeLineContract, data: data, actionName: "Cancel Vault");
      await refreshBalances();
      return true;
    } catch(e) {
      errorMessage = e.toString().replaceAll("Exception:", "").trim();
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}

// ==============================================================
// 4. ENTRY POINT & THEME
// ==============================================================
void main() {
  debugPrint('🔥 TRACE: Initializing LifeLine Protocol on Celo Mainnet...');
  runApp(MultiProvider(providers: [ChangeNotifierProvider(create: (_) => CeloWalletProvider())], child: const LifeLineApp()));
}

class AppTheme {
  static const Color bg = Color(0xFF071310);
  static const Color card = Color(0xFF0D1F18);
  static const Color card2 = Color(0xFF122B20);
  static const Color border = Color(0xFF1E3D2C);
  static const Color green = Color(0xFF35D07F);
  static const Color gold = Color(0xFFFBCC5C);
  static const Color cream = Color(0xFFF0EBE0);
  static const Color muted = Color(0xFF6B8F7A);
  static const Color red = Color(0xFFF46B6B);
  static const Color orange = Color(0xFFF5A623);

  static ThemeData get themeData => ThemeData(scaffoldBackgroundColor: bg, textTheme: GoogleFonts.dmSansTextTheme().apply(bodyColor: cream, displayColor: cream));
}

class LifeLineApp extends StatelessWidget {
  const LifeLineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'LifeLine Protocol', theme: AppTheme.themeData, debugShowCheckedModeBanner: false, home: const MobileAppShell());
  }
}

class MobileAppShell extends StatefulWidget {
  const MobileAppShell({super.key});

  @override
  State<MobileAppShell> createState() => _MobileAppShellState();
}

class _MobileAppShellState extends State<MobileAppShell> {
  int _currentScreen = 0;
  int? _selectedVaultId;

  String? _claimVaultId;
  String? _claimPayload;
  String? _claimToken;

  @override
  void initState() {
    super.initState();
    final params = parseWebUrlParams();
    if (params.containsKey('vaultId') && params.containsKey('payload')) {
      _claimVaultId = params['vaultId'];
      _claimPayload = params['payload'];
      _claimToken = params['token'];
      _currentScreen = 4;
    }
  }

  void _navigate(int screenIndex, {int? vaultId}) {
    setState(() {
      _currentScreen = screenIndex;
      if (vaultId != null) _selectedVaultId = vaultId;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: SelectionArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300), 
            transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child), 
            child: _getScreenWidget()
          ),
        ),
      ),
    );
  }

  Widget _getScreenWidget() {
    switch (_currentScreen) {
      case 0: return WelcomeScreen(key: const ValueKey(0), onNext: () => _navigate(1));
      case 1: return DashboardScreen(
        key: const ValueKey(1), 
        onVaultClick: (id) => _navigate(3, vaultId: id), 
        onCreateClick: () => _navigate(2),
        onDisconnectClick: () => _navigate(0)
      );
      case 2: return CreateVaultScreen(key: const ValueKey(2), onBack: () => _navigate(1), onSubmit: () => _navigate(1));
      case 3: return VaultDetailScreen(key: const ValueKey(3), vaultId: _selectedVaultId!, onBack: () => _navigate(1), onForceClaim: () => _navigate(4));
      case 4: return ClaimScreen(
        key: const ValueKey(4), 
        onBack: () => _navigate(1),
        vaultId: _claimVaultId,
        payload: _claimPayload,
        tokenAddr: _claimToken,
      );
      default: return const SizedBox();
    }
  }
}

// ==============================================================
// 5. MOBILE / WEB SCREENS
// ==============================================================
class WelcomeScreen extends StatefulWidget {
  final VoidCallback onNext;
  const WelcomeScreen({super.key, required this.onNext});
  @override State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final PageController _pageController = PageController();
  final FocusNode _focusNode = FocusNode();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _pages = [
    {
      "title": "Welcome to LifeLine",
      "description": "The decentralized inheritance protocol. Secure your crypto assets and ensure they pass to your loved ones when you can't be there.",
      "icon": LucideIcons.shieldCheck,
      "color": AppTheme.gold
    },
    {
      "title": "Zero Counterparty Risk",
      "description": "Your assets are locked in a Celo smart contract. No central authority can touch them. Only your mathematical proof can unlock them.",
      "icon": LucideIcons.lock,
      "color": AppTheme.green
    },
    {
      "title": "Proof of Life Timer", 
      "description": "Set a custom inactivity duration. As long as you ping the app, your vault stays locked. If your timer expires, it safely unlocks for your beneficiary.",
      "icon": LucideIcons.timer,
      "color": AppTheme.orange
    },
    {
      "title": "Ready to Start?", 
      "description": "Connect your Web3 wallet or open via MiniPay to deploy your first secure legacy vault.",
      "icon": LucideIcons.wallet,
      "color": AppTheme.green
    }
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _showWalletSelector(BuildContext context, CeloWalletProvider wallet) {
    if (isMiniPay()) {
      debugPrint('[Wallet UI] MiniPay environment detected. Routing natively...');
      wallet.connectProvider(ethereum, context).then((_) {
        if (wallet.isConnected) widget.onNext();
      });
      return; 
    }

    showDialog(
      context: context,
      builder: (ctx) {
         return Center(
           child: Material(
             color: Colors.transparent,
             child: Container(
               width: 360,
               padding: const EdgeInsets.all(24),
               decoration: BoxDecoration(color: AppTheme.card, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(20)),
               child: Column(
                 mainAxisSize: MainAxisSize.min,
                 children: [
                   Row(
                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                     children: [
                        const Text("Connect Wallet", style: TextStyle(color: AppTheme.cream, fontSize: 18, fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.close, color: AppTheme.muted), onPressed: () => Navigator.pop(ctx))
                     ]
                   ),
                   const SizedBox(height: 16),
                   _buildWalletOpt("MetaMask", "Injected", Icons.pets, Colors.orange, () { Navigator.pop(ctx); wallet.connectProvider(ethereum, context).then((_) { if(wallet.isConnected) widget.onNext(); }); }),
                   _buildWalletOpt("Coinbase Wallet", "Extension", Icons.account_balance_wallet, Colors.blue, () { Navigator.pop(ctx); final p = coinbaseWalletExtension ?? ((ethereum?.isCoinbaseWallet == true) ? ethereum : null); wallet.connectProvider(p, context).then((_) { if(wallet.isConnected) widget.onNext(); }); }),
                   _buildWalletOpt("Trust Wallet", "Injected", Icons.shield, Colors.lightBlue, () { Navigator.pop(ctx); final p = trustWallet ?? ((ethereum?.isTrust == true) ? ethereum : null); wallet.connectProvider(p, context).then((_) { if(wallet.isConnected) widget.onNext(); }); }),
                   _buildWalletOpt("Phantom", "EVM Ready", Icons.visibility, Colors.deepPurple, () { Navigator.pop(ctx); final p = phantomWallet ?? ((ethereum?.isPhantom == true) ? ethereum : null); wallet.connectProvider(p, context).then((_) { if(wallet.isConnected) widget.onNext(); }); }),
                   _buildWalletOpt("Rabby Wallet", "Extension", Icons.security, Colors.indigoAccent, () { Navigator.pop(ctx); final p = (ethereum != null && ethereum!.isRabby == true) ? ethereum : null; wallet.connectProvider(p, context).then((_) { if(wallet.isConnected) widget.onNext(); }); }),
                 ]
               )
             )
           )
         );
      }
    );
  }

  Widget _buildWalletOpt(String name, String sub, IconData icon, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(color: AppTheme.card2, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 16),
              Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.cream)),
              const Spacer(),
              Text(sub, style: const TextStyle(fontSize: 12, color: AppTheme.muted))
            ]
          )
        )
      )
    );
  }

  @override 
  Widget build(BuildContext context) {
    final wallet = context.watch<CeloWalletProvider>();
    
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent || event is KeyRepeatEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowRight || event.logicalKey == LogicalKeyboardKey.pageDown || event.logicalKey == LogicalKeyboardKey.space) {
                if (_currentPage < _pages.length - 1) {
                  _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                  return KeyEventResult.handled;
                }
              } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft || event.logicalKey == LogicalKeyboardKey.pageUp) {
                if (_currentPage > 0) {
                  _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                  return KeyEventResult.handled;
                }
              }
            }
            return KeyEventResult.ignored;
          },
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: AppTheme.gold.withOpacity(0.08), border: Border.all(color: AppTheme.gold.withOpacity(0.2)), borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppTheme.gold, shape: BoxShape.circle)), const SizedBox(width: 8), const Text("Celo Mainnet", style: TextStyle(color: AppTheme.gold, fontSize: 12, fontWeight: FontWeight.w500))])),
                  
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      onPageChanged: (int page) => setState(() => _currentPage = page),
                      itemCount: _pages.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.all(40.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 100, height: 100,
                                decoration: BoxDecoration(
                                  color: _pages[index]["color"].withOpacity(0.1),
                                  border: Border.all(color: _pages[index]["color"].withOpacity(0.3)),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _pages[index]["icon"],
                                  size: 48,
                                  color: _pages[index]["color"],
                                ),
                              ),
                              const SizedBox(height: 40),
                              Text(
                                _pages[index]["title"],
                                style: GoogleFonts.cormorantGaramond(fontSize: 32, fontWeight: FontWeight.w600, color: AppTheme.cream),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                _pages[index]["description"],
                                style: const TextStyle(fontSize: 15, color: AppTheme.muted, height: 1.6),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  
                  if (wallet.errorMessage != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 10.0), child: Text(wallet.errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.red, fontSize: 13, fontWeight: FontWeight.w500))),
                  if (wallet.isLoading) Padding(padding: const EdgeInsets.symmetric(vertical: 24.0), child: Column(children: [const CircularProgressIndicator(color: AppTheme.green), const SizedBox(height: 12), Text(wallet.loadingStatus, style: const TextStyle(color: AppTheme.muted, fontSize: 12))])),

                  if (!wallet.isLoading)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _pages.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          height: 6,
                          width: _currentPage == index ? 24 : 6,
                          decoration: BoxDecoration(
                            color: _currentPage == index ? AppTheme.green : AppTheme.card2,
                            border: Border.all(color: _currentPage == index ? AppTheme.green : AppTheme.border),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  
                  const SizedBox(height: 40),
                  
                  if (!wallet.isLoading)
                    Padding(
                      padding: const EdgeInsets.only(left: 40.0, right: 40.0, bottom: 40.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _currentPage == _pages.length - 1 ? AppTheme.card : AppTheme.green,
                            side: _currentPage == _pages.length - 1 ? const BorderSide(color: AppTheme.green) : BorderSide.none,
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          onPressed: () {
                            if (_currentPage == _pages.length - 1) {
                              _showWalletSelector(context, wallet);
                            } else {
                              _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                            }
                          },
                          child: Text(
                            _currentPage == _pages.length - 1 ? (isMiniPay() ? "Open in MiniPay" : "Connect Web3 Wallet") : "Next",
                            style: TextStyle(
                              fontSize: 16, 
                              fontWeight: FontWeight.w600, 
                              color: _currentPage == _pages.length - 1 ? AppTheme.green : AppTheme.bg
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  final Function(int) onVaultClick;
  final VoidCallback onCreateClick;
  final VoidCallback onDisconnectClick;
  
  const DashboardScreen({super.key, required this.onVaultClick, required this.onCreateClick, required this.onDisconnectClick});
  @override State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ScrollController _scrollController = ScrollController();
  
  Widget _buildVaultCard(BuildContext context, Map<String, dynamic> vault, String type, String amt, String sym, String time, bool isExpired, VoidCallback onTap) {
    final bool isActive = vault['isActive'] ?? true;
    final int vaultId = vault['id'];

    String status = "ACTIVE";
    if (!isActive) {
      status = "CLOSED";
    } else if (isExpired) {
      status = "UNLOCKED";
    }

    Widget cardContent = Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppTheme.card2, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Vault #$vaultId", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)), const SizedBox(height: 4), Text(type, style: const TextStyle(fontSize: 12, color: AppTheme.muted))]), 
            if (status == "ACTIVE")
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppTheme.green.withOpacity(0.1), border: Border.all(color: AppTheme.green.withOpacity(0.2)), borderRadius: BorderRadius.circular(8)), child: const Text("Active", style: TextStyle(fontSize: 11, color: AppTheme.green, fontWeight: FontWeight.w600)))
            else if (status == "UNLOCKED")
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppTheme.orange.withOpacity(0.1), border: Border.all(color: AppTheme.orange.withOpacity(0.2)), borderRadius: BorderRadius.circular(8)), child: const Text("Unlocked", style: TextStyle(fontSize: 11, color: AppTheme.orange, fontWeight: FontWeight.w600)))
            else
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppTheme.red.withOpacity(0.1), border: Border.all(color: AppTheme.red.withOpacity(0.2)), borderRadius: BorderRadius.circular(8)), child: const Text("Closed", style: TextStyle(fontSize: 11, color: AppTheme.red, fontWeight: FontWeight.w600)))
          ]),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
            RichText(text: TextSpan(children: [TextSpan(text: "$amt ", style: GoogleFonts.cormorantGaramond(fontSize: 24, fontWeight: FontWeight.w600, color: AppTheme.cream)), TextSpan(text: sym, style: const TextStyle(fontSize: 14, color: AppTheme.muted, fontWeight: FontWeight.w500))])), 
            if (status == "ACTIVE")
              Row(children: [Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppTheme.orange, shape: BoxShape.circle)), const SizedBox(width: 6), Text(time, style: GoogleFonts.spaceMono(fontSize: 13, color: AppTheme.orange, fontWeight: FontWeight.w600))])
          ]),
          if (status == "UNLOCKED") ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16), width: double.infinity,
              decoration: BoxDecoration(color: AppTheme.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.orange.withOpacity(0.3))),
              child: Column(
                children: [
                  const Text("VAULT UNLOCKED 🔓", style: TextStyle(color: AppTheme.orange, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.info_outline, size: 16, color: AppTheme.orange),
                    const SizedBox(width: 8),
                    Expanded(child: Text("Secure access link has been sent. Please advise the beneficiary to check their Spam/Junk folder.", style: TextStyle(color: AppTheme.muted, fontSize: 13, height: 1.4))),
                  ]),
                ],
              ),
            )
          ],
          if (status == "CLOSED") ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), 
              width: double.infinity,
              decoration: BoxDecoration(color: AppTheme.green.withOpacity(0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.green.withOpacity(0.2))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("VAULT CLAIMED / CANCELLED ✓", style: TextStyle(color: AppTheme.green, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 11)),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppTheme.card,
                            title: const Text("Dismiss Vault History?", style: TextStyle(color: AppTheme.cream)),
                            content: const Text("This will permanently hide this closed vault from your dashboard view. It remains stored on the blockchain safely.", style: TextStyle(color: AppTheme.muted)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel", style: TextStyle(color: AppTheme.muted))),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  final provider = Provider.of<CeloWalletProvider>(context, listen: false);
                                  provider.dismissVault(vaultId);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vault removed from local view."), backgroundColor: AppTheme.muted));
                                },
                                child: const Text("Dismiss", style: TextStyle(color: AppTheme.cream)),
                              ),
                            ],
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppTheme.border)),
                        child: Row(
                          children: const [
                            Icon(LucideIcons.trash, size: 14, color: AppTheme.muted),
                            SizedBox(width: 6),
                            Text("Dismiss", style: TextStyle(fontSize: 11, color: AppTheme.muted, fontWeight: FontWeight.w600))
                          ]
                        )
                      )
                    )
                  )
                ]
              ),
            )
          ]
        ],
      ),
    );

    if (status == "CLOSED") {
      return Dismissible(
        key: Key('vault_$vaultId'),
        direction: DismissDirection.endToStart,
        background: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: AppTheme.red, borderRadius: BorderRadius.circular(18)),
          alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20),
          child: const Icon(LucideIcons.trash, color: AppTheme.cream),
        ),
        onDismissed: (direction) {
          final provider = Provider.of<CeloWalletProvider>(context, listen: false);
          provider.dismissVault(vaultId);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vault removed from local view."), backgroundColor: AppTheme.muted));
        },
        child: cardContent,
      );
    }

    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: cardContent));
  }

  @override Widget build(BuildContext context) {
    final wallet = context.watch<CeloWalletProvider>();
    final shortAddress = wallet.userAddress != null ? "${wallet.userAddress!.substring(0,6)}...${wallet.userAddress!.substring(wallet.userAddress!.length - 4)}" : "Not Connected";

    return Stack(
      children: [
        KeyboardScrollWrapper(
          controller: _scrollController,
          child: RefreshIndicator(
            color: AppTheme.green, backgroundColor: AppTheme.card2,
            onRefresh: () async => await wallet.refreshBalances(),
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Good morning", style: TextStyle(fontSize: 13, color: AppTheme.muted)),
                        Text("A User", style: GoogleFonts.cormorantGaramond(fontSize: 24, fontWeight: FontWeight.w600)),
                        Container(margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppTheme.card2, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(8)), child: Row(children: [Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF4CD9A0), shape: BoxShape.circle)), const SizedBox(width: 6), Text(shortAddress, style: GoogleFonts.spaceMono(fontSize: 11, color: AppTheme.muted, fontWeight: FontWeight.w600))]))
                      ],
                    ),
                    InkWell(
                      onTap: () {
                         wallet.disconnectWallet();
                         widget.onDisconnectClick();
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(width: 44, height: 44, decoration: BoxDecoration(color: AppTheme.card2, border: Border.all(color: AppTheme.red.withOpacity(0.3)), borderRadius: BorderRadius.circular(12)), child: const Icon(LucideIcons.logOut, color: AppTheme.red, size: 20)),
                    )
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF0F2D1E), Color(0xFF162E21)]), border: Border.all(color: AppTheme.green.withOpacity(0.15)), borderRadius: BorderRadius.circular(20)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("TOTAL AVAILABLE", style: TextStyle(fontSize: 11, color: AppTheme.muted, letterSpacing: 1, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      RichText(text: TextSpan(children: [
                        TextSpan(text: wallet.isSyncingBalances ? "..." : (wallet.tokenBalances['USDC']?.toStringAsFixed(2) ?? "0.00"), style: GoogleFonts.cormorantGaramond(fontSize: 36, fontWeight: FontWeight.w600, color: AppTheme.cream)), 
                        const TextSpan(text: " USDC", style: TextStyle(fontSize: 16, color: AppTheme.green, fontWeight: FontWeight.w500))
                      ])),
                      const SizedBox(height: 16),
                      Row(children: [_buildMiniBal("CELO", wallet.isSyncingBalances ? "..." : (wallet.tokenBalances['CELO']?.toStringAsFixed(2) ?? "0.00"))])
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text("My Vaults", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.cream)), 
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: widget.onCreateClick, 
                      child: const Text("+ New Vault", style: TextStyle(fontSize: 13, color: AppTheme.green, fontWeight: FontWeight.w500))
                    )
                  )
                ]),
                const SizedBox(height: 16),
                
                if (wallet.isSyncingVaults && wallet.activeVaults.isEmpty)
                  const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppTheme.green)))
                else if (wallet.activeVaults.isEmpty && !wallet.isSyncingVaults)
                  Container(padding: const EdgeInsets.all(32), decoration: BoxDecoration(color: AppTheme.card2, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)), child: const Center(child: Text("No active vaults found.", style: TextStyle(color: AppTheme.muted, fontSize: 13))))
                else
                  ...wallet.activeVaults.map((vault) {
                    final isEmail = vault['heir'] == "0x0000000000000000000000000000000000000000";
                    final typeLabel = isEmail ? "Email Claim" : "Wallet Claim";
                    
                    return LiveTimer(
                      unlockTimeEpoch: vault['unlockTime'],
                      onExpire: () => wallet.autoDispatchEmail(vault['id'], context),
                      builder: (days, hrs, mins, secs, isExpired) {
                        final timeLabel = isExpired ? "EXPIRED" : "${days}d ${hrs}h ${mins}m";
                        return _buildVaultCard(context, vault, typeLabel, vault['balance'].toStringAsFixed(2), vault['tokenSymbol'], timeLabel, isExpired, () => widget.onVaultClick(vault['id']));
                      }
                    );
                  }).toList(),
                
                const SizedBox(height: 80), 
              ],
            ),
          ),
        ),
        Positioned(bottom: 24, right: 20, child: FloatingActionButton.large(backgroundColor: AppTheme.green, onPressed: widget.onCreateClick, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), child: const Icon(LucideIcons.plus, color: AppTheme.bg, size: 32)))
      ],
    );
  }

  Widget _buildMiniBal(String sym, String val) {
    return Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)), child: Column(children: [Text(sym, style: const TextStyle(fontSize: 11, color: AppTheme.muted, fontWeight: FontWeight.w600)), const SizedBox(height: 4), Text(val, style: GoogleFonts.spaceMono(fontSize: 12, color: AppTheme.cream, fontWeight: FontWeight.w600))])));
  }
}

class CreateVaultScreen extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onSubmit;
  const CreateVaultScreen({super.key, required this.onBack, required this.onSubmit});
  @override State<CreateVaultScreen> createState() => _CreateVaultScreenState();
}

class _CreateVaultScreenState extends State<CreateVaultScreen> {
  final ScrollController _scrollController = ScrollController();
  bool emailMode = true;
  String selectedToken = "USDC";
  String _timeUnit = "Days";
  
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _pinCtrl = TextEditingController();
  final TextEditingController _walletCtrl = TextEditingController();
  final TextEditingController _amountCtrl = TextEditingController(text: "1");
  final TextEditingController _durationCtrl = TextEditingController(text: "30");

  void _handleCreateVault(CeloWalletProvider wallet) async {
    final amount = double.tryParse(_amountCtrl.text) ?? 0.0;
    int durationVal = int.tryParse(_durationCtrl.text) ?? 0;
    
    int multiplier = 86400;
    if (_timeUnit == "Seconds") multiplier = 1;
    else if (_timeUnit == "Minutes") multiplier = 60;
    else if (_timeUnit == "Hours") multiplier = 3600;
    else if (_timeUnit == "Days") multiplier = 86400;
    else if (_timeUnit == "Months") multiplier = 2592000;
    
    int durationSeconds = durationVal * multiplier;

    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter a valid amount"), backgroundColor: AppTheme.red));
      return;
    }
    if (!wallet.hasSufficientBalance(selectedToken, amount)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Insufficient $selectedToken balance"), backgroundColor: AppTheme.red));
      return;
    }
    if (emailMode && (_pinCtrl.text.length < 6 || _emailCtrl.text.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter valid Email and 6-Digit PIN"), backgroundColor: AppTheme.red));
      return;
    }
    if (!emailMode && _walletCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter a valid EVM address"), backgroundColor: AppTheme.red));
      return;
    }

    final success = await wallet.initializeVault(
      tokenSymbol: selectedToken, amountStr: _amountCtrl.text.trim(), durationSeconds: durationSeconds,
      isEmailMode: emailMode, heirName: _nameCtrl.text.isNotEmpty ? _nameCtrl.text : "Beneficiary",
      heirEmail: emailMode ? _emailCtrl.text.trim() : null, pin: emailMode ? _pinCtrl.text.trim() : null,
      directWalletAddress: !emailMode ? _walletCtrl.text.trim() : null,
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vault Initialized successfully!"), backgroundColor: AppTheme.green));
      widget.onSubmit();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(wallet.errorMessage ?? "Transaction failed"), backgroundColor: AppTheme.red, duration: const Duration(seconds: 5)));
    }
  }

  Widget _buildStepperRow(String text, int status) {
    Color color = status == 2 ? AppTheme.green : (status == 1 ? AppTheme.orange : AppTheme.muted);
    IconData icon = status == 2 ? LucideIcons.checkCircle : (status == 1 ? LucideIcons.loader : LucideIcons.circle);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          if (status == 1)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppTheme.orange, strokeWidth: 2))
          else
            Icon(icon, color: color, size: 20),
          const SizedBox(width: 16),
          Text(text, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w600)),
        ]
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<CeloWalletProvider>();
    final double? parsedAmount = double.tryParse(_amountCtrl.text);

    return KeyboardScrollWrapper(
      controller: _scrollController,
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          Row(children: [
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: widget.onBack, 
                child: Container(width: 40, height: 40, decoration: BoxDecoration(color: AppTheme.card2, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(12)), child: const Icon(LucideIcons.chevronLeft, size: 20, color: AppTheme.cream))
              )
            ), 
            const SizedBox(width: 16), 
            Text("New Vault", style: GoogleFonts.cormorantGaramond(fontSize: 24, fontWeight: FontWeight.w600))
          ]),
          const SizedBox(height: 28),
          
          const Text("BENEFICIARY", style: TextStyle(fontSize: 12, color: AppTheme.muted, letterSpacing: 0.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _buildTextField(_nameCtrl, "Heir Name (e.g. Mama Ngozi)"),
          const SizedBox(height: 12),
          
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppTheme.card2, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(14)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                children: [
                  const Text("Email claim", style: TextStyle(fontSize: 15, color: AppTheme.cream, fontWeight: FontWeight.w500)),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: "We generate a secure key and pre-fund it with gas so your heir can claim without needing crypto.",
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(12),
                    textStyle: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: BoxDecoration(color: AppTheme.card, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(LucideIcons.info, size: 16, color: AppTheme.muted),
                  )
                ],
              ), 
              const SizedBox(height: 4), 
              const Text("Require PIN to unlock", style: TextStyle(fontSize: 12, color: AppTheme.muted))
            ]), 
            Switch(value: emailMode, onChanged: (v) => setState(() => emailMode = v), activeColor: AppTheme.green, activeTrackColor: AppTheme.green.withOpacity(0.3))
          ])),
          
          const SizedBox(height: 12),
          if (emailMode) ...[
            _buildTextField(_emailCtrl, "heir@example.com"), const SizedBox(height: 12), 
            _buildTextField(_pinCtrl, "6-Digit Security PIN", obscure: true, isNumber: true, maxLength: 6),
          ] else ...[
            _buildTextField(_walletCtrl, "0x EVM wallet address"),
          ],
          
          const SizedBox(height: 28),
          const Text("ASSET TO LOCK", style: TextStyle(fontSize: 12, color: AppTheme.muted, letterSpacing: 0.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(children: ["USDC", "CELO"].map((t) => Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => setState(() => selectedToken = t), 
                child: AnimatedContainer(duration: const Duration(milliseconds: 200), margin: const EdgeInsets.only(right: 10), padding: const EdgeInsets.symmetric(vertical: 14), decoration: BoxDecoration(color: AppTheme.card2, border: Border.all(color: selectedToken == t ? AppTheme.green : AppTheme.border), borderRadius: BorderRadius.circular(12)), child: Center(child: Text(t, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: selectedToken == t ? AppTheme.green : AppTheme.muted))))
              )
            )
          )).toList()),
          const SizedBox(height: 12),
          StatefulBuilder(
            builder: (context, setInnerState) => Container(
              decoration: BoxDecoration(color: AppTheme.card2, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(12)),
              child: TextField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 15, color: AppTheme.cream),
                onChanged: (v) => setState((){}), 
                decoration: InputDecoration(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), border: InputBorder.none, hintText: "Amount", counterText: "", hintStyle: const TextStyle(color: AppTheme.muted)),
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.only(top: 8.0, left: 4), child: Text("Available: ${wallet.tokenBalances[selectedToken]?.toStringAsFixed(2) ?? '0.00'} $selectedToken", style: const TextStyle(color: AppTheme.muted, fontSize: 11))),
          
          const SizedBox(height: 28),
          const Text("INACTIVITY TIMER", style: TextStyle(fontSize: 12, color: AppTheme.muted, letterSpacing: 0.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(flex: 2, child: _buildTextField(_durationCtrl, "30", isNumber: true)), 
            const SizedBox(width: 10), 
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: AppTheme.card2, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(12)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _timeUnit,
                    dropdownColor: AppTheme.card,
                    isExpanded: true,
                    icon: const Icon(LucideIcons.chevronDown, color: AppTheme.muted, size: 18),
                    style: const TextStyle(color: AppTheme.cream, fontSize: 15, fontWeight: FontWeight.w500),
                    items: ["Seconds", "Minutes", "Hours", "Days", "Months"].map((String value) {
                      return DropdownMenuItem<String>(value: value, child: Text(value));
                    }).toList(),
                    onChanged: (v) => setState(() => _timeUnit = v!),
                  ),
                ),
              ),
            )
          ]),
          
          const SizedBox(height: 36),

          if (parsedAmount != null && parsedAmount > 0)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(color: AppTheme.green.withOpacity(0.05), border: Border.all(color: AppTheme.green.withOpacity(0.2)), borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Transaction Summary", style: TextStyle(color: AppTheme.cream, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Asset to Lock", style: TextStyle(color: AppTheme.muted, fontSize: 13)), Text("${_amountCtrl.text} $selectedToken", style: const TextStyle(color: AppTheme.cream, fontSize: 13, fontWeight: FontWeight.w600))]),
                  if (emailMode) ...[
                    const SizedBox(height: 8),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Claim Link Gas Fee", style: TextStyle(color: AppTheme.muted, fontSize: 13)), const Text("0.02 CELO", style: TextStyle(color: AppTheme.cream, fontSize: 13, fontWeight: FontWeight.w600))]),
                  ],
                  const SizedBox(height: 12),
                  const Divider(color: AppTheme.border),
                  const SizedBox(height: 8),
                  Text(emailMode ? "Note: You will be asked to sign up to 3 transactions to ensure complete decentralized security." : "Note: You will be asked to sign up to 2 transactions to ensure decentralized security.", style: const TextStyle(color: AppTheme.green, fontSize: 11, fontStyle: FontStyle.italic)),
                ]
              )
            ),

          if (wallet.isLoading)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: AppTheme.card2, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Deploying Vault", style: TextStyle(color: AppTheme.cream, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  _buildStepperRow("Approve Asset", wallet.loadingStatus.contains("Step 1") ? 1 : (wallet.loadingStatus.contains("Step 2") || wallet.loadingStatus.contains("Step 3") ? 2 : 0)),
                  _buildStepperRow("Lock Vault On-Chain", wallet.loadingStatus.contains("Step 2") ? 1 : (wallet.loadingStatus.contains("Step 3") ? 2 : 0)),
                  if (emailMode)
                    _buildStepperRow("Pre-fund Claim Link", wallet.loadingStatus.contains("Step 3") ? 1 : 0),
                ]
              )
            )
          else
            InkWell(
              onTap: () => _handleCreateVault(wallet),
              borderRadius: BorderRadius.circular(16),
              child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 18), decoration: BoxDecoration(color: AppTheme.green, borderRadius: BorderRadius.circular(16)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(LucideIcons.lock, color: AppTheme.bg, size: 18), SizedBox(width: 8), Text("Initialize & Lock Vault", style: TextStyle(color: AppTheme.bg, fontSize: 16, fontWeight: FontWeight.w600))])),
            ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String hint, {bool obscure = false, bool isNumber = false, int? maxLength}) {
    return Container(
      decoration: BoxDecoration(color: AppTheme.card2, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(12)),
      child: TextField(
        controller: ctrl, obscureText: obscure, maxLength: maxLength, style: const TextStyle(fontSize: 15, color: AppTheme.cream),
        keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        decoration: InputDecoration(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), border: InputBorder.none, hintText: hint, counterText: "", hintStyle: const TextStyle(color: AppTheme.muted)),
      ),
    );
  }
}

class VaultDetailScreen extends StatefulWidget {
  final int vaultId;
  final VoidCallback onBack;
  final VoidCallback onForceClaim;
  const VaultDetailScreen({super.key, required this.vaultId, required this.onBack, required this.onForceClaim});
  @override State<VaultDetailScreen> createState() => _VaultDetailScreenState();
}

class _VaultDetailScreenState extends State<VaultDetailScreen> {
  final ScrollController _scrollController = ScrollController();

  void _showAmountDialog(BuildContext context, String title, Function(String) onConfirm) {
    final TextEditingController ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(title, style: const TextStyle(color: AppTheme.cream)),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: AppTheme.cream),
          decoration: const InputDecoration(labelText: 'Amount', labelStyle: TextStyle(color: AppTheme.muted)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel", style: TextStyle(color: AppTheme.muted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.green),
            onPressed: () {
              final val = double.tryParse(ctrl.text);
              if (val != null && val > 0) {
                Navigator.pop(ctx);
                onConfirm(ctrl.text.trim());
              }
            },
            child: const Text("Confirm", style: TextStyle(color: AppTheme.bg)),
          ),
        ],
      ),
    );
  }

  void _showCancelConfirmation(BuildContext context, Function() onConfirm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: const Text("Cancel Vault?", style: TextStyle(color: AppTheme.red)),
        content: const Text("This will close the vault and refund all assets immediately.", style: TextStyle(color: AppTheme.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Keep Vault", style: TextStyle(color: AppTheme.cream))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () { Navigator.pop(ctx); onConfirm(); },
            child: const Text("Close Vault", style: TextStyle(color: AppTheme.cream)),
          ),
        ],
      ),
    );
  }

  void _triggerEmail(BuildContext context, CeloWalletProvider wallet) async {
    final claimUrl = web.window.localStorage.getItem('ll_claim_${widget.vaultId}');
    final token = web.window.localStorage.getItem('ll_token_${widget.vaultId}');
    final amount = web.window.localStorage.getItem('ll_amount_${widget.vaultId}');

    if (claimUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Email URL not found on this device."), backgroundColor: AppTheme.red));
      return;
    }

    final TextEditingController emailCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: const Text("Send Inheritance Link", style: TextStyle(color: AppTheme.cream)),
        content: TextField(controller: emailCtrl, style: const TextStyle(color: AppTheme.cream), decoration: const InputDecoration(labelText: 'Heir Email', labelStyle: TextStyle(color: AppTheme.muted))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel", style: TextStyle(color: AppTheme.muted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.green),
            onPressed: () async {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Dispatching..."), backgroundColor: AppTheme.orange));
              final success = await EmailService.sendInheritanceEmail(
                heirName: "Beneficiary", heirEmail: emailCtrl.text.trim(), ownerName: "A User",
                message: "Here is your secure access link.", claimUrl: claimUrl, amount: amount ?? "0", tokenSymbol: token ?? "USDC",
              );
              if(context.mounted) {
                if (success) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Email Sent Successfully!"), backgroundColor: AppTheme.green));
                else ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to send email."), backgroundColor: AppTheme.red));
              }
            },
            child: const Text("Send Now", style: TextStyle(color: AppTheme.bg)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<CeloWalletProvider>();
    final vault = wallet.activeVaults.firstWhere((v) => v['id'] == widget.vaultId, orElse: () => {});
    
    if (vault.isEmpty) return const Scaffold(backgroundColor: AppTheme.bg, body: Center(child: CircularProgressIndicator(color: AppTheme.green)));

    final bool isActiveOnChain = vault['isActive'] ?? true;

    return KeyboardScrollWrapper(
      controller: _scrollController,
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          Row(children: [
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: widget.onBack, 
                child: Container(width: 40, height: 40, decoration: BoxDecoration(color: AppTheme.card2, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(12)), child: const Icon(LucideIcons.chevronLeft, size: 20, color: AppTheme.cream))
              )
            ), 
            const SizedBox(width: 16), 
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Vault #${widget.vaultId}", style: GoogleFonts.cormorantGaramond(fontSize: 26, fontWeight: FontWeight.w600)), const SizedBox(height: 4), Text("${vault['balance'].toStringAsFixed(2)} ${vault['tokenSymbol']}", style: const TextStyle(fontSize: 13, color: AppTheme.muted))]))
          ]),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF0F2D1E), Color(0xFF0D1E16)]), border: Border.all(color: AppTheme.green.withOpacity(0.12)), borderRadius: BorderRadius.circular(20)),
            child: Column(
              children: [
                const Text("TIME UNTIL RELEASE", style: TextStyle(fontSize: 11, color: AppTheme.muted, letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                LiveTimer(
                  unlockTimeEpoch: vault['unlockTime'],
                  onExpire: () => wallet.autoDispatchEmail(widget.vaultId, context),
                  builder: (days, hrs, mins, secs, isExpired) {
                    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [_buildTimeBox(days, "DAYS"), const Text(" : ", style: TextStyle(color: AppTheme.muted, fontSize: 24)), _buildTimeBox(hrs, "HRS"), const Text(" : ", style: TextStyle(color: AppTheme.muted, fontSize: 24)), _buildTimeBox(mins, "MIN"), const Text(" : ", style: TextStyle(color: AppTheme.muted, fontSize: 24)), _buildTimeBox(secs, "SEC")]);
                  }
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          
          if (isActiveOnChain) ...[
            InkWell(
              onTap: wallet.isLoading ? null : () async {
                final success = await wallet.pingVault(widget.vaultId);
                if (success && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Timer Reset Successfully"), backgroundColor: AppTheme.green));
                else if (!success && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(wallet.errorMessage ?? "Failed"), backgroundColor: AppTheme.red));
              },
              child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 20), decoration: BoxDecoration(color: wallet.isLoading ? AppTheme.muted : AppTheme.green, borderRadius: BorderRadius.circular(16)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [wallet.isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppTheme.bg, strokeWidth: 2)) : const Icon(LucideIcons.heartPulse, color: AppTheme.bg, size: 20), const SizedBox(width: 8), Text(wallet.isLoading ? wallet.loadingStatus : "I'm Alive — Reset Timer", style: const TextStyle(color: AppTheme.bg, fontSize: 16, fontWeight: FontWeight.w600))])),
            ),
            const SizedBox(height: 28),
            
            Row(children: [
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _showAmountDialog(context, "Add Funds (${vault['tokenSymbol']})", (amountStr) async {
                      final success = await wallet.addFunds(widget.vaultId, vault['tokenSymbol'], amountStr);
                      if (success && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Funds Added Successfully"), backgroundColor: AppTheme.green));
                      else if (!success && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(wallet.errorMessage ?? "Failed"), backgroundColor: AppTheme.red));
                    }), 
                    child: Container(padding: const EdgeInsets.symmetric(vertical: 16), decoration: BoxDecoration(color: AppTheme.card2, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(14)), child: const Center(child: Text("+ Funds", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500))))
                  )
                )
              ), 
              const SizedBox(width: 12),
              
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _showAmountDialog(context, "Withdraw Funds (${vault['tokenSymbol']})", (amountStr) async {
                      final success = await wallet.withdrawFunds(widget.vaultId, vault['tokenSymbol'], amountStr);
                      if (success && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Funds Withdrawn Successfully"), backgroundColor: AppTheme.green));
                      else if (!success && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(wallet.errorMessage ?? "Failed"), backgroundColor: AppTheme.red));
                    }), 
                    child: Container(padding: const EdgeInsets.symmetric(vertical: 16), decoration: BoxDecoration(color: AppTheme.card2, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(14)), child: const Center(child: Text("Withdraw", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500))))
                  )
                )
              ), 
              const SizedBox(width: 12),
              
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _showCancelConfirmation(context, () async {
                      final success = await wallet.cancelVault(widget.vaultId);
                      if (success && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vault Cancelled Successfully"), backgroundColor: AppTheme.green));
                        widget.onBack();
                      } else if (!success && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(wallet.errorMessage ?? "Failed"), backgroundColor: AppTheme.red));
                    }), 
                    child: Container(padding: const EdgeInsets.symmetric(vertical: 16), decoration: BoxDecoration(color: AppTheme.card2, border: Border.all(color: AppTheme.red.withOpacity(0.3)), borderRadius: BorderRadius.circular(14)), child: const Center(child: Text("Cancel", style: TextStyle(fontSize: 14, color: AppTheme.red, fontWeight: FontWeight.w500))))
                  )
                )
              ),
            ]),
            const SizedBox(height: 28),
          ],
          
          Container(
            padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppTheme.green.withOpacity(0.05), border: Border.all(color: AppTheme.green.withOpacity(0.1)), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Force dispatch email now", style: TextStyle(fontSize: 13, color: AppTheme.muted, fontWeight: FontWeight.w500)), const SizedBox(height: 10), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Test Inheritance Flow", style: TextStyle(fontSize: 14, color: AppTheme.cream)), MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: () => _triggerEmail(context, wallet), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: AppTheme.card2, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(10)), child: const Text("Trigger", style: TextStyle(fontSize: 13, color: AppTheme.muted, fontWeight: FontWeight.w600)))))])])
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildTimeBox(String val, String unit) {
    return Column(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(10)), child: Text(val, style: GoogleFonts.spaceMono(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.cream))), const SizedBox(height: 6), Text(unit, style: const TextStyle(fontSize: 10, color: AppTheme.muted, fontWeight: FontWeight.w600))]);
  }
}

class ClaimScreen extends StatefulWidget {
  final VoidCallback onBack;
  final String? vaultId;
  final String? payload;
  final String? tokenAddr;

  const ClaimScreen({super.key, required this.onBack, this.vaultId, this.payload, this.tokenAddr});
  @override State<ClaimScreen> createState() => _ClaimScreenState();
}

class _ClaimScreenState extends State<ClaimScreen> {
  final ScrollController _scrollController = ScrollController();
  int filled = 0;
  String pinBuffer = "";
  bool isProcessing = false;
  String statusMsg = "Awaiting your claim";

  final String _lifeLineAbi = '[{"inputs":[{"internalType":"uint64","name":"vaultId","type":"uint64"}],"name":"getVault","outputs":[{"components":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"address","name":"heirAddress","type":"address"},{"internalType":"bytes32","name":"heirPubkey","type":"bytes32"},{"internalType":"address","name":"token","type":"address"},{"internalType":"uint256","name":"balance","type":"uint256"},{"internalType":"uint64","name":"unlockTime","type":"uint64"},{"internalType":"uint64","name":"inactivityDuration","type":"uint64"},{"internalType":"bool","name":"isActive","type":"bool"}],"internalType":"struct LifeLine.Vault","name":"","type":"tuple"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint64","name":"vaultId","type":"uint64"},{"internalType":"bytes32","name":"sigR","type":"bytes32"},{"internalType":"bytes32","name":"sigS","type":"bytes32"},{"internalType":"uint8","name":"sigV","type":"uint8"}],"name":"claimInheritance","outputs":[],"stateMutability":"nonpayable","type":"function"}]';
  final String _erc20Abi = '[{"constant":false,"inputs":[{"name":"_to","type":"address"},{"name":"_value","type":"uint256"}],"name":"transfer","outputs":[{"name":"","type":"bool"}],"type":"function"}, {"constant":true,"inputs":[{"name":"_owner","type":"address"}],"name":"balanceOf","outputs":[{"name":"balance","type":"uint256"}],"type":"function"}]';

  void _showWalletModal(String privateKeyHex, String vaultId, String tokenAddr) {
    showModalBottomSheet(
      context: context, backgroundColor: AppTheme.card, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(mainAxisSize: MainAxisSize.min, children: [const Text("Connect to Claim", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.cream)), const SizedBox(height: 24), _buildWalletOption("MiniPay / Web3 Wallet", LucideIcons.smartphone, () { Navigator.pop(context); _executeOnChainClaim(privateKeyHex, vaultId, tokenAddr); })]),
        );
      }
    );
  }

  Widget _buildWalletOption(String name, IconData icon, VoidCallback onTap) {
    return InkWell(onTap: onTap, child: Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppTheme.card2, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(16)), child: Row(children: [Icon(icon, color: AppTheme.green), const SizedBox(width: 16), Text(name, style: const TextStyle(fontSize: 16, color: AppTheme.cream, fontWeight: FontWeight.w500))])));
  }

  void handleKey(String k) async {
    if (isProcessing) return;
    if (k == "del") { setState(() { if (filled > 0) { filled--; pinBuffer = pinBuffer.substring(0, pinBuffer.length - 1); } }); } 
    else if (k == "ok" && filled == 6) { _verifyAndPromptWallet(); } 
    else if (k != "ok" && filled < 6) { setState(() { filled++; pinBuffer += k; }); }
  }

  Future<void> _verifyAndPromptWallet() async {
    setState(() { isProcessing = true; statusMsg = "Verifying Link..."; });
    try {
      String? vaultIdStr = widget.vaultId; 
      String? payload = widget.payload;
      String? tokenAddr = widget.tokenAddr ?? AppConstants.tokens['USDC']!['address'];

      if (payload == null) {
        final storedUrl = web.window.localStorage.getItem('ll_claim_${vaultIdStr ?? "1"}');
        if (storedUrl != null) {
          final queryStr = storedUrl.substring(storedUrl.indexOf('?') + 1);
          final storedParams = Uri.splitQueryString(queryStr);
          payload = storedParams['payload'];
          tokenAddr = storedParams['token'] ?? tokenAddr;
        }
      }

      if (payload == null) throw Exception("Invalid Claim URL. Missing encrypted key.");

      setState(() => statusMsg = "Decrypting Ephemeral Key...");
      
      final privateKeyHex = EvmEncryptionService.decryptWithPin(payload.replaceAll(" ", "+"), pinBuffer);
      _showWalletModal(privateKeyHex, vaultIdStr ?? "1", tokenAddr!);
    } catch (e) {
      debugPrint('🔥 TRACE: Decrypt Link Error: $e');
      setState(() { statusMsg = e.toString().contains("INVALID_PIN") ? "Error: Invalid 6-Digit PIN." : "Error: ${e.toString().replaceAll("Exception:", "").trim()}"; isProcessing = false; pinBuffer = ""; filled = 0; });
    }
  }

  Future<void> _executeOnChainClaim(String privateKeyHex, String vaultIdStr, String tokenAddr) async {
    try {
      final wallet = context.read<CeloWalletProvider>();
      
      if (!wallet.isConnected) {
        await wallet.connectProvider(ethereum, context);
      }
      
      if (!wallet.isConnected) throw Exception("Wallet connection required to receive funds.");

      final ephemeralCredentials = EthPrivateKey.fromHex(privateKeyHex);
      final web3client = Web3Client(AppConstants.rpcUrl, http.Client());
      final llContract = DeployedContract(ContractAbi.fromJson(_lifeLineAbi, 'LifeLine'), EthereumAddress.fromHex(AppConstants.lifeLineContract, enforceEip55: false));
      final erc20 = DeployedContract(ContractAbi.fromJson(_erc20Abi, 'ERC20'), EthereumAddress.fromHex(tokenAddr, enforceEip55: false));

      setState(() => statusMsg = "Checking Vault Status...");
      final vaultRes = await web3client.call(contract: llContract, function: llContract.function('getVault'), params: [BigInt.parse(vaultIdStr)]);
      final vaultData = vaultRes.first as List<dynamic>;
      final isActive = vaultData[7] as bool;
      
      final balanceOfFunc = erc20.function('balanceOf');
      final balRes = await web3client.call(contract: erc20, function: balanceOfFunc, params: [ephemeralCredentials.address]);
      BigInt sweepAmount = balRes.first as BigInt;

      if (!isActive && sweepAmount == BigInt.zero) {
        throw Exception("This vault has already been fully claimed and swept to your wallet.");
      }

      if (isActive) {
        setState(() => statusMsg = "Unlocking Vault on Celo...");
        final claimFunc = llContract.function('claimInheritance');

        final claimTx = await web3client.sendTransaction(
          ephemeralCredentials,
          Transaction.callContract(contract: llContract, function: claimFunc, parameters: [BigInt.parse(vaultIdStr), Uint8List(32), Uint8List(32), BigInt.zero]),
          chainId: AppConstants.chainId,
        );
        debugPrint('🔥 TRACE: Claimed successfully! Tx: $claimTx');
        
        setState(() => statusMsg = "Waiting for block confirmation...");
        await Future.delayed(const Duration(seconds: 4)); 

        final updatedBalRes = await web3client.call(contract: erc20, function: balanceOfFunc, params: [ephemeralCredentials.address]);
        sweepAmount = updatedBalRes.first as BigInt;
      } else {
        debugPrint('🔥 TRACE: Vault already unlocked on contract. Direct recovery initiated.');
      }

      setState(() => statusMsg = "Sweeping funds to your wallet...");

      if (tokenAddr.toLowerCase() == AppConstants.tokens['CELO']!['address'].toLowerCase()) {
        final gasPrice = await web3client.getGasPrice();
        final exactGasCost = gasPrice.getInWei * BigInt.from(21000); 

        if (sweepAmount > exactGasCost) {
          final exactSweepAmount = sweepAmount - exactGasCost;
          debugPrint('🔥 TRACE: Type 0 Exact Sweep. Cost: $exactGasCost, Sweeping: $exactSweepAmount Wei');
          
          final sweepTx = await web3client.sendTransaction(
            ephemeralCredentials,
            Transaction(
              to: EthereumAddress.fromHex(wallet.userAddress!, enforceEip55: false),
              value: EtherAmount.inWei(exactSweepAmount),
              maxGas: 21000, 
              gasPrice: gasPrice, 
            ),
            chainId: AppConstants.chainId,
          );
          debugPrint('🔥 TRACE: Native Recovery Sweep Complete! Tx: $sweepTx');
        } else {
          throw Exception("Insufficient balance to cover exact transfer network fees.");
        }
      } else {
        final transferFunc = erc20.function('transfer');
        final sweepTx = await web3client.sendTransaction(
          ephemeralCredentials,
          Transaction.callContract(
            contract: erc20, 
            function: transferFunc, 
            parameters: [EthereumAddress.fromHex(wallet.userAddress!, enforceEip55: false), sweepAmount]
          ),
          chainId: AppConstants.chainId,
        );
        debugPrint('🔥 TRACE: ERC20 Recovery Sweep Complete! Tx: $sweepTx');
      }

      setState(() { statusMsg = "CLAIM SUCCESSFUL ✓"; isProcessing = false; });
    } catch (e) {
      debugPrint('🔥 TRACE: On-Chain Claim Error: $e'); 
      setState(() { statusMsg = "Error: ${e.toString().replaceAll("Exception:", "").trim()}"; isProcessing = false; pinBuffer = ""; filled = 0; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, leading: IconButton(icon: const Icon(LucideIcons.x, color: AppTheme.muted), onPressed: widget.onBack)),
      body: SafeArea(
        child: KeyboardScrollWrapper(
          controller: _scrollController,
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: AppTheme.gold.withOpacity(0.08), border: Border.all(color: AppTheme.gold.withOpacity(0.2)), borderRadius: BorderRadius.circular(20)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(LucideIcons.shieldCheck, color: AppTheme.gold, size: 14), SizedBox(width: 8), Text("Sent by LifeLine Protocol", style: TextStyle(color: AppTheme.gold, fontSize: 12, fontWeight: FontWeight.w500))])),
                  const SizedBox(height: 24),
                  Container(width: 80, height: 80, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF1A2E10), Color(0xFF2A4A1A)]), border: Border.all(color: AppTheme.gold.withOpacity(0.25)), borderRadius: BorderRadius.circular(24)), child: const Icon(LucideIcons.key, color: AppTheme.gold, size: 36)),
                  const SizedBox(height: 16),
                  Text("You have a\npending inheritance", textAlign: TextAlign.center, style: GoogleFonts.cormorantGaramond(fontSize: 28, fontWeight: FontWeight.w600, height: 1.1)),
                  const SizedBox(height: 8),
                  Container(margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16), padding: const EdgeInsets.symmetric(vertical: 24), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF0F2D1E), Color(0xFF162E21)]), border: Border.all(color: AppTheme.green.withOpacity(0.15)), borderRadius: BorderRadius.circular(20)), child: Center(child: Column(children: [Text("Unlock Vault", style: GoogleFonts.cormorantGaramond(fontSize: 32, fontWeight: FontWeight.w600, color: AppTheme.cream)), const SizedBox(height: 6), Text(statusMsg, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: statusMsg.contains("Error") ? AppTheme.red : AppTheme.green, fontWeight: FontWeight.w500))]))),
                  const SizedBox(height: 40),
                  const Text("Enter 6-digit security PIN to unlock", style: TextStyle(fontSize: 14, color: AppTheme.muted, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 16),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(6, (i) => AnimatedContainer(duration: const Duration(milliseconds: 150), margin: const EdgeInsets.symmetric(horizontal: 6), width: 16, height: 16, decoration: BoxDecoration(color: i < filled ? AppTheme.green : AppTheme.card2, border: Border.all(color: i < filled ? AppTheme.green : AppTheme.border), shape: BoxShape.circle)))),
                  const SizedBox(height: 32),
                  if (isProcessing) const CircularProgressIndicator(color: AppTheme.green)
                  else Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: GridView.count(shrinkWrap: true, crossAxisCount: 3, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 2.2, physics: const NeverScrollableScrollPhysics(), children: ["1","2","3","4","5","6","7","8","9","del","0","ok"].map((k) => 
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => handleKey(k), 
                            child: Container(decoration: BoxDecoration(color: k == "ok" ? AppTheme.green : AppTheme.card2, border: Border.all(color: k == "ok" ? AppTheme.green : AppTheme.border), borderRadius: BorderRadius.circular(14)), child: Center(child: k == "del" ? const Icon(LucideIcons.delete, size: 22, color: AppTheme.muted) : k == "ok" ? const Icon(LucideIcons.arrowRight, size: 24, color: AppTheme.bg) : Text(k, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500))))
                          )
                        )
                      ).toList()),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}