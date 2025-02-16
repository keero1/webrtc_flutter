import { WebSocketServer } from "ws";

const wss = new WebSocketServer({ port: 3000 }); 

let sender = null;
let receiver = null;

wss.on("connection", (ws) => {
  ws.on("message", (message) => {
    const data = JSON.parse(message);

    switch (data.type) {
      case "sender":
        sender = ws;
        console.log("Sender connected");
        if (receiver) {
          receiver?.send(
            JSON.stringify({
              type: "senderActive",
              message: "sender has connected to webRTC",
            })
          );
        }

        break;

      case "receiver":
        receiver = ws;
        console.log("Receiver connected");
        break;

      case "offer":
        if (receiver) {
          console.log("Forwarding SDP Offer to receiver...");
          receiver.send(JSON.stringify(data));
        } else {
          console.log("Receiver is not connected!");
        }
        break;

      case "answer":
        if (sender) {
          console.log("Forwarding SDP Answer to sender...");
          sender.send(JSON.stringify(data));
        } else {
          console.log("Sender is not connected!");
        }
        break;

      case "ice":
        console.log("Forwarding ICE Candidate...");
        if (data.target === "receiver" && receiver) {
          receiver.send(JSON.stringify(data));
        } else if (data.target === "sender" && sender) {
          sender.send(JSON.stringify(data));
        } else {
          console.log("ICE candidate target missing!");
          sender?.send(
            JSON.stringify({
              type: "error",
              message: "Receiver is not available yet. Please wait.",
            })
          );
        }
        break;
    }
  });

  ws.on("close", () => {
    if (ws === sender) {
      sender = null;
      console.log("Sender disconnected");

      if (receiver) {
        console.log("Receiver is active.");
        receiver.send(
          JSON.stringify({
            type: "statusUpdate",
            message: "Sender has disconnected.",
          })
        );
      }
    }
    if (ws === receiver) {
      receiver = null;
      console.log("Receiver disconnected");

      if (sender) {
        sender.send(
          JSON.stringify({
            type: "statusUpdate",
            message: "Receiver has disconnected. Disconnecting sender.",
          })
        );
        sender.close();
      }
    }
  });
});

console.log("WebSocket signaling server running on ws://localhost:3000");
