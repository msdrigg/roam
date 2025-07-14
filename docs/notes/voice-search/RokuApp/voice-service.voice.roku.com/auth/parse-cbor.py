
#!/usr/bin/env python3
"""
Roku Mobile App Attestation Flow Replication
Based on analysis of fh.a, fh.b, fh.d, gh.a, ch.b classes
"""

import json
import base64
import uuid
from cryptography.hazmat.backends import default_backend
import cbor2
import base64


def parse_auth_attestation():
    with open("./attestation-result.b64", "rb") as f:
        binary_data = f.read()
    # Decode the Base64 encoded CBOR data
    binary_data = base64.b64decode(binary_data)
    parsed = cbor2.loads(binary_data)
    # // Load to json 
    json_data = json.dumps(parsed, indent=2, cls=JSONEncoder)
    print(json_data)

class JSONEncoder(json.JSONEncoder):
    """Custom JSON encoder to handle bytes and UUIDs"""
    
    def default(self, obj):
        if isinstance(obj, bytes):
            # Print as hex
            return obj.hex()
        elif isinstance(obj, uuid.UUID):
            return str(obj)  # Convert UUID to string
        return super().default(obj)

if __name__ == "__main__":
    parse_auth_attestation()