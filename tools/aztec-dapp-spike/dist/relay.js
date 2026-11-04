(() => {
  // ../aztec-account/node_modules/@aztec-labs/wallet-sdk/dest/crypto.js
  var HKDF_INFO = new TextEncoder().encode("Aztec Wallet DAPP Key derivation");
  var FINGERPRINT_DATA = new TextEncoder().encode("aztec-wallet-verification-verificationHash");

  // ../aztec-account/node_modules/@aztec-labs/wallet-sdk/dest/types.js
  var WalletMessageType = /* @__PURE__ */ (function(WalletMessageType2) {
    WalletMessageType2["DISCOVERY"] = "aztec-wallet-discovery";
    WalletMessageType2["DISCOVERY_RESPONSE"] = "aztec-wallet-discovery-response";
    WalletMessageType2["DISCONNECT"] = "aztec-wallet-disconnect";
    WalletMessageType2["KEY_EXCHANGE_REQUEST"] = "aztec-wallet-key-exchange-request";
    WalletMessageType2["KEY_EXCHANGE_RESPONSE"] = "aztec-wallet-key-exchange-response";
    WalletMessageType2["WALLET_READY"] = "aztec-wallet-ready";
    WalletMessageType2["SECURE_MESSAGE"] = "aztec-wallet-secure-message";
    WalletMessageType2["SECURE_RESPONSE"] = "aztec-wallet-secure-response";
    WalletMessageType2["SESSION_DISCONNECTED"] = "aztec-wallet-session-disconnected";
    WalletMessageType2["PING"] = "aztec-wallet-ping";
    WalletMessageType2["PONG"] = "aztec-wallet-pong";
    return WalletMessageType2;
  })({});

  // ../aztec-account/node_modules/@aztec-labs/wallet-sdk/dest/extension/handlers/internal_message_types.js
  var InternalMessageType = {
    // Content script → Background
    DISCOVERY_REQUEST: "discovery-request",
    KEY_EXCHANGE_REQUEST: "key-exchange-request",
    SECURE_MESSAGE: "secure-message",
    DISCONNECT_REQUEST: "disconnect-request",
    PING: "ping",
    // Background → Content script
    DISCOVERY_APPROVED: "discovery-approved",
    KEY_EXCHANGE_RESPONSE: "key-exchange-response",
    SECURE_RESPONSE: "secure-response",
    SESSION_DISCONNECTED: "session-disconnected",
    PONG: "pong"
  };
  var MessageOrigin = {
    BACKGROUND: "background",
    CONTENT_SCRIPT: "content-script"
  };

  // ../aztec-account/node_modules/@aztec-labs/wallet-sdk/dest/extension/handlers/content_script_connection_handler.js
  var ContentScriptConnectionHandler = class {
    transport;
    ports;
    listening;
    pageMessageHandler;
    constructor(transport) {
      this.transport = transport;
      this.ports = /* @__PURE__ */ new Map();
      this.listening = false;
      this.pageMessageHandler = null;
      this.handleBackgroundMessage = (message) => {
        if (message.origin !== MessageOrigin.BACKGROUND) {
          return;
        }
        const { type, sessionId, content } = message;
        switch (type) {
          case InternalMessageType.DISCOVERY_APPROVED:
            this.handleDiscoveryApproved(sessionId, content);
            break;
          case InternalMessageType.KEY_EXCHANGE_RESPONSE:
            this.handleKeyExchangeResponse(sessionId, content);
            break;
          case InternalMessageType.SECURE_RESPONSE:
            this.handleSecureResponse(sessionId, content);
            break;
          case InternalMessageType.SESSION_DISCONNECTED:
            this.handleSessionDisconnected(sessionId);
            break;
          case InternalMessageType.PONG:
            this.handlePong(sessionId);
            break;
        }
      };
    }
    start() {
      if (this.listening) {
        return;
      }
      this.transport.addBackgroundListener(this.handleBackgroundMessage);
      this.pageMessageHandler = (event) => {
        if (event.source !== window) {
          return;
        }
        let data;
        try {
          data = JSON.parse(event.data);
        } catch {
          return;
        }
        if (!data?.type) {
          return;
        }
        if (data.type === WalletMessageType.DISCOVERY) {
          this.handleDiscoveryRequest(data);
        }
      };
      window.addEventListener("message", this.pageMessageHandler);
      this.listening = true;
    }
    handleBackgroundMessage;
    handlePong(sessionId) {
      const connection = this.ports.get(sessionId);
      if (!connection) {
        return;
      }
      connection.port.postMessage({
        type: WalletMessageType.PONG
      });
    }
    handleDiscoveryRequest(request) {
      this.transport.sendToBackground({
        origin: MessageOrigin.CONTENT_SCRIPT,
        type: InternalMessageType.DISCOVERY_REQUEST,
        content: request
      });
    }
    handleDiscoveryApproved(sessionId, walletInfo) {
      const channel = new MessageChannel();
      this.ports.set(sessionId, {
        port: channel.port1,
        sessionId
      });
      channel.port1.onmessage = (event) => {
        const data = event.data;
        switch (data?.type) {
          case WalletMessageType.KEY_EXCHANGE_REQUEST:
            this.transport.sendToBackground({
              origin: MessageOrigin.CONTENT_SCRIPT,
              type: InternalMessageType.KEY_EXCHANGE_REQUEST,
              sessionId,
              content: data
            });
            break;
          case WalletMessageType.DISCONNECT:
            this.transport.sendToBackground({
              origin: MessageOrigin.CONTENT_SCRIPT,
              type: InternalMessageType.DISCONNECT_REQUEST,
              sessionId,
              content: data
            });
            break;
          case WalletMessageType.PING:
            this.transport.sendToBackground({
              origin: MessageOrigin.CONTENT_SCRIPT,
              type: InternalMessageType.PING,
              sessionId
            });
            break;
          default:
            this.transport.sendToBackground({
              origin: MessageOrigin.CONTENT_SCRIPT,
              type: InternalMessageType.SECURE_MESSAGE,
              sessionId,
              content: data
            });
            break;
        }
      };
      channel.port1.start();
      const response = {
        type: WalletMessageType.DISCOVERY_RESPONSE,
        requestId: sessionId,
        walletInfo
      };
      window.postMessage(JSON.stringify(response), "*", [
        channel.port2
      ]);
    }
    handleKeyExchangeResponse(sessionId, response) {
      const connection = this.ports.get(sessionId);
      if (!connection) {
        return;
      }
      connection.port.postMessage(response);
    }
    handleSecureResponse(sessionId, content) {
      const connection = this.ports.get(sessionId);
      if (!connection) {
        return;
      }
      connection.port.postMessage(content);
    }
    handleSessionDisconnected(sessionId) {
      const connection = this.ports.get(sessionId);
      if (!connection) {
        return;
      }
      connection.port.postMessage({
        type: WalletMessageType.DISCONNECT
      });
      connection.port.close();
      this.ports.delete(sessionId);
    }
    closeConnection(sessionId) {
      const connection = this.ports.get(sessionId);
      if (connection) {
        connection.port.close();
        this.ports.delete(sessionId);
      }
    }
    closeAllConnections() {
      for (const [sessionId, connection] of this.ports) {
        connection.port.close();
        this.ports.delete(sessionId);
      }
    }
    getConnectionCount() {
      return this.ports.size;
    }
  };

  // web/relay.js
  if (!window.__casberiRelay) {
    window.__casberiRelay = true;
    let deliver = null;
    const relay = new ContentScriptConnectionHandler({
      sendToBackground: (message) => window.webkit.messageHandlers.casberiRelay.postMessage(JSON.stringify(message)),
      addBackgroundListener: (handler) => {
        deliver = handler;
      }
    });
    window.__casberiDeliver = (json) => deliver?.(JSON.parse(json));
    relay.start();
  }
})();
