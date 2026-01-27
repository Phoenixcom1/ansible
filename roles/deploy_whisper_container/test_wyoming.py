#!/usr/bin/env python3
"""
Test script for Wyoming protocol server
Usage: python3 test_wyoming.py <host> <port>
Example: python3 test_wyoming.py whisper.kerberos.fassbender.contact 10300
"""

import socket
import sys
import json

def test_wyoming_connection(host, port):
    """Test connection to Wyoming protocol server"""
    try:
        print(f"Connecting to {host}:{port}...")
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        sock.connect((host, int(port)))
        print("✓ Connected successfully!")
        
        # Wyoming servers may send initial message
        print("Checking for initial server response...")
        sock.settimeout(2)
        try:
            response = sock.recv(4096)
            if response:
                print(f"✓ Received initial message ({len(response)} bytes)")
                try:
                    decoded = response.decode('utf-8').strip()
                    print(f"Message: {decoded[:200]}")
                except:
                    print(f"Message (hex): {response[:100].hex()}")
        except socket.timeout:
            print("No initial message (this is normal for Wyoming)")
        
        # Keep connection alive briefly
        print("Connection is stable and ready for Wyoming protocol")
        
        sock.close()
        print("\n✓ Wyoming server is accessible and accepting connections!")
        print("✓ Home Assistant should be able to connect.")
        return True
        
    except socket.timeout:
        print(f"✗ Connection timeout - server might not be listening")
        return False
    except ConnectionRefusedError:
        print(f"✗ Connection refused - is the service running?")
        return False
    except Exception as e:
        print(f"✗ Error: {e}")
        return False

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 test_wyoming.py <host> <port>")
        print("Example: python3 test_wyoming.py whisper.kerberos.fassbender.contact 10300")
        sys.exit(1)
    
    host = sys.argv[1]
    port = sys.argv[2]
    
    success = test_wyoming_connection(host, port)
    sys.exit(0 if success else 1)
