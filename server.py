import socket
import json
import threading

# Server IP and Port
SERVER_IP = '0.0.0.0'  # Accepts connections from any IP
SERVER_PORT = 4509    # Choose any free port

# Create a TCP socket
server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server_socket.bind((SERVER_IP, SERVER_PORT))
server_socket.listen(5)
print(f"🔔 Server is listening on {SERVER_IP}:{SERVER_PORT}")

clients = []
clients_lock = threading.Lock()

def handle_client(client_socket, client_address):
    print(f"✅ Connected with {client_address}")
    with client_socket:
        with clients_lock:
            clients.append(client_socket)
        try: 
            while True:
                data = client_socket.recv(1024).decode()
                if not data:
                    break
                if not data.strip():
                    continue  # Ignore empty messages
                print(f"📨 Received: {data}")
                # Forward the received message to all other clients
                broadcast_message(data, exclude=client_socket)
        except ConnectionResetError:
            print("❌ Connection closed by client")
        finally:
            with clients_lock:
                if client_socket in clients:
                    clients.remove(client_socket)
            print(f"🔌 Disconnected from {client_address}")

def broadcast_message(message, exclude=None):
    with clients_lock:
        for c in clients:
            if c is not exclude:
                try:
                    c.sendall((message + "\n").encode())
                except Exception as e:
                    print(f"❌ Could not send to a client: {e}")

if __name__ == "__main__":
    while True:
        client_socket, client_address = server_socket.accept()
        threading.Thread(target=handle_client, args=(client_socket, client_address), daemon=True).start()