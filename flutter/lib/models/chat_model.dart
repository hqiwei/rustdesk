import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:draggable_float_widget/draggable_float_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:window_manager/window_manager.dart';

import '../../mobile/widgets/overlay.dart';
import '../common.dart';
import 'model.dart';

class MessageBody {
  ChatUser chatUser;
  List<ChatMessage> chatMessages;
  MessageBody(this.chatUser, this.chatMessages);

  void insert(ChatMessage cm) {
    this.chatMessages.insert(0, cm);
  }

  void clear() {
    this.chatMessages.clear();
  }
}

class ChatModel with ChangeNotifier {
  static final clientModeID = -1;

  /// _overlayState:
  /// Desktop: store session overlay by using [setOverlayState].
  /// Mobile: always null, use global overlay.
  /// see [_getOverlayState] in [showChatIconOverlay] or [showChatWindowOverlay]
  OverlayState? _overlayState;
  OverlayEntry? chatIconOverlayEntry;
  OverlayEntry? chatWindowOverlayEntry;

  final ChatUser me = ChatUser(
    id: "",
    firstName: "Me",
  );

  late final Map<int, MessageBody> _messages = Map()
    ..[clientModeID] = MessageBody(me, []);

  var _currentID = clientModeID;
  late bool _isShowChatPage = false;

  Map<int, MessageBody> get messages => _messages;

  int get currentID => _currentID;

  bool get isShowChatPage => _isShowChatPage;

  WeakReference<FFI> _ffi;

  /// Constructor
  ChatModel(this._ffi);

  ChatUser get currentUser {
    final user = messages[currentID]?.chatUser;
    if (user == null) {
      _currentID = clientModeID;
      return me;
    } else {
      return user;
    }
  }

  setOverlayState(OverlayState? os) {
    _overlayState = os;
  }

  OverlayState? _getOverlayState() {
    if (_overlayState == null) {
      if (globalKey.currentState == null ||
          globalKey.currentState!.overlay == null) return null;
      return globalKey.currentState!.overlay;
    } else {
      return _overlayState;
    }
  }

  showChatIconOverlay({Offset offset = const Offset(200, 50)}) {
    if (chatIconOverlayEntry != null) {
      chatIconOverlayEntry!.remove();
    }
    // mobile check navigationBar
    final bar = navigationBarKey.currentWidget;
    if (bar != null) {
      if ((bar as BottomNavigationBar).currentIndex == 1) {
        return;
      }
    }

    final overlayState = _getOverlayState();
    if (overlayState == null) return;

    final overlay = OverlayEntry(builder: (context) {
      return DraggableFloatWidget(
          config: DraggableFloatWidgetBaseConfig(
            initPositionYInTop: false,
            initPositionYMarginBorder: 100,
            borderTopContainTopBar: true,
          ),
          child: FloatingActionButton(
              onPressed: () {
                if (chatWindowOverlayEntry == null) {
                  showChatWindowOverlay();
                } else {
                  hideChatWindowOverlay();
                }
              },
              child: Icon(Icons.message)));
    });
    overlayState.insert(overlay);
    chatIconOverlayEntry = overlay;
  }

  hideChatIconOverlay() {
    if (chatIconOverlayEntry != null) {
      chatIconOverlayEntry!.remove();
      chatIconOverlayEntry = null;
    }
  }

  showChatWindowOverlay() {
    if (chatWindowOverlayEntry != null) return;
    final overlayState = _getOverlayState();
    if (overlayState == null) return;
    final overlay = OverlayEntry(builder: (context) {
      return DraggableChatWindow(
          position: Offset(20, 80), width: 250, height: 350, chatModel: this);
    });
    overlayState.insert(overlay);
    chatWindowOverlayEntry = overlay;
  }

  hideChatWindowOverlay() {
    if (chatWindowOverlayEntry != null) {
      chatWindowOverlayEntry!.remove();
      chatWindowOverlayEntry = null;
      return;
    }
  }

  toggleChatOverlay() {
    if (chatIconOverlayEntry == null || chatWindowOverlayEntry == null) {
      gFFI.invokeMethod("enable_soft_keyboard", true);
      showChatIconOverlay();
      showChatWindowOverlay();
    } else {
      hideChatIconOverlay();
      hideChatWindowOverlay();
    }
  }

  toggleCMChatPage(int id) async {
    if (gFFI.chatModel.currentID != id) {
      gFFI.chatModel.changeCurrentID(id);
    }
    if (_isShowChatPage) {
      _isShowChatPage = !_isShowChatPage;
      notifyListeners();
      await windowManager.setSize(Size(400, 600));
    } else {
      await windowManager.setSize(Size(800, 600));
      await Future.delayed(Duration(milliseconds: 100));
      _isShowChatPage = !_isShowChatPage;
      notifyListeners();
    }
  }

  changeCurrentID(int id) {
    if (_messages.containsKey(id)) {
      _currentID = id;
      notifyListeners();
    } else {
      final client = _ffi.target?.serverModel.clients
          .firstWhere((client) => client.id == id);
      if (client == null) {
        return debugPrint(
            "Failed to changeCurrentID,remote user doesn't exist");
      }
      final chatUser = ChatUser(
        id: client.peerId,
        firstName: client.name,
      );
      _messages[id] = MessageBody(chatUser, []);
      _currentID = id;
      notifyListeners();
    }
  }

  receive(int id, String text) async {
    if (text.isEmpty) return;
    // mobile: first message show overlay icon
    if (chatIconOverlayEntry == null) {
      showChatIconOverlay();
    }
    // desktop: show chat page
    if (!_isShowChatPage) {
      toggleCMChatPage(id);
    }
    _ffi.target?.serverModel.jumpTo(id);

    late final chatUser;
    if (id == clientModeID) {
      chatUser = ChatUser(
        firstName: _ffi.target?.ffiModel.pi.username,
        id: await bind.mainGetLastRemoteId(),
      );
    } else {
      final client = _ffi.target?.serverModel.clients
          .firstWhere((client) => client.id == id);
      if (client == null) {
        return debugPrint("Failed to receive msg,user doesn't exist");
      }
      if (isDesktop) {
        window_on_top(null);
        var index = _ffi.target?.serverModel.clients
            .indexWhere((client) => client.id == id);
        if (index != null && index >= 0) {
          gFFI.serverModel.tabController.jumpTo(index);
        }
      }
      chatUser = ChatUser(id: client.peerId, firstName: client.name);
    }

    if (!_messages.containsKey(id)) {
      _messages[id] = MessageBody(chatUser, []);
    }
    _messages[id]!.insert(
        ChatMessage(text: text, user: chatUser, createdAt: DateTime.now()));
    _currentID = id;
    notifyListeners();
  }

  send(ChatMessage message) {
    if (message.text.isNotEmpty) {
      _messages[_currentID]?.insert(message);
      if (_currentID == clientModeID) {
        if (_ffi.target != null) {
          bind.sessionSendChat(id: _ffi.target!.id, text: message.text);
        }
      } else {
        bind.cmSendChat(connId: _currentID, msg: message.text);
      }
    }
    notifyListeners();
  }

  close() {
    hideChatIconOverlay();
    hideChatWindowOverlay();
    _overlayState = null;
    notifyListeners();
  }

  resetClientMode() {
    _messages[clientModeID]?.clear();
  }
}
