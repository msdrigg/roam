#!/usr/bin/env python3
"""
Roku Mobile App Attestation Flow Replication
Based on analysis of fh.a, fh.b, fh.d, gh.a, ch.b classes
"""

import json
import base64
import uuid
import secrets
import requests
from dataclasses import dataclass, asdict
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.backends import default_backend
from typing import Optional
import os
import base64

@dataclass
class RokuDeviceState:
    """Complete device state for Roku attestation"""
    
    # RSA Keypair (stored as PEM strings for JSON serialization)
    private_key_pem: str
    public_key_pem: str
    public_key_der_b64: str  # DER format, Base64 encoded (for clientKey)
    
    # Device Identifiers (equivalent to Android device IDs)
    device_id: str           # x-roku-reserved-dev-id (64 char hex)
    client_id: str           # x-roku-reserved-client-id (UUID)
    profile_id: str          # x-roku-reserved-profile-id (UUID)
    session_id: str          # x-roku-reserved-session-id (UUID)
    request_id: str          # x-roku-reserved-request-id (UUID)
    correlation_id: str      # x-roku-reserved-correlation (UUID with prefix)
    
    # App/Platform Info
    app_version: str = "12.6.0"
    os_name: str = "ios"
    os_version: str = "15.8.2"
    platform_version: str = "2.0"
    app_name: str = "remote"
    
    # Locale/Region
    culture_code: str = "en_US"
    locale: str = "en_US"
    timezone_offset: str = "+00:00"
    channel_store_code: str = "us"
    
    # Attestation State
    last_challenge: Optional[str] = None
    registration_token: Optional[str] = None
    token_expiration: Optional[int] = None

def generate_device_state() -> RokuDeviceState:
    """Generate new device state with RSA keypair and random IDs"""
    print("🔑 Generating new RSA keypair...")
    
    # Generate 2048-bit RSA keypair (matching Android KeyStore default)
    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048,
        backend=default_backend()
    )
    public_key = private_key.public_key()
    
    # Serialize keys
    private_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption()
    ).decode('utf-8')
    
    public_pem = public_key.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo
    ).decode('utf-8')
    
    # DER format for clientKey (matching Android getEncoded())
    public_der = public_key.public_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PublicFormat.SubjectPublicKeyInfo
    )
    public_der_b64 = base64.b64encode(public_der).decode('utf-8')
    
    print(f"📱 Generating device identifiers...")
    
    # Generate device identifiers (matching Roku's format)
    device_id = secrets.token_hex(20)  # 40-char hex string
    client_id = str(uuid.uuid4()).upper()
    profile_id = str(uuid.uuid4()).upper()
    session_id = str(uuid.uuid4()).upper()
    request_id = str(uuid.uuid4()).upper()
    correlation_id = f"mob_{str(uuid.uuid4()).upper()}"
    
    return RokuDeviceState(
        private_key_pem=private_pem,
        public_key_pem=public_pem,
        public_key_der_b64=public_der_b64,
        device_id=device_id,
        client_id=client_id,
        profile_id=profile_id,
        session_id=session_id,
        request_id=request_id,
        correlation_id=correlation_id
    )

def load_or_create_device_state() -> RokuDeviceState:
    """Load device state from file or create new one"""
    state_file = "./roku-state.json"
    
    if os.path.exists(state_file):
        print("📂 Loading existing device state from roku-state.json")
        with open(state_file, 'r') as f:
            state_data = json.load(f)
            return RokuDeviceState(**state_data)
    else:
        print("🆕 Creating new device state")
        state = generate_device_state()
        
        # Save to file
        with open(state_file, 'w') as f:
            json.dump(asdict(state), f, indent=2)
        print(f"💾 Saved device state to {state_file}")
        
        return state

def generate_attestation_result(challenge: str, device_state: RokuDeviceState) -> str:
    """
    Generate attestation result (integrity token)
    This simulates the fh.g.integrityTokenHelper.h() method
    In reality, this might use Google Play Integrity API or similar
    """
    # Create a plausible attestation payload
    attestation_data = {
        "challenge": challenge,
        "deviceId": device_state.device_id,
        "clientId": device_state.client_id,
        "appVersion": device_state.app_version,
        "osName": device_state.os_name,
        "osVersion": device_state.os_version,
        "timestamp": 1703980800,  # Example timestamp
        "integrity": "DEVICE_VERIFIED",
        "packageName": "com.roku.remote"
    }
    
    # Convert to JSON and encode
    attestation_json = json.dumps(attestation_data, separators=(',', ':'))
    attestation_b64 = base64.b64encode(attestation_json.encode('utf-8')).decode('utf-8')
    
    # Make it look more like a real integrity token (longer)
    padding = base64.b64encode(secrets.token_bytes(200)).decode('utf-8')
    return f"{attestation_b64}.{padding}"

def get_challenge(device_state: RokuDeviceState) -> str:
    """Get challenge from Roku server"""
    url = f"https://auth.prod.mobile.roku.com/client/{device_state.client_id}/challenge"
    
    headers = {
        "Accept": "application/json",
        "User-Agent": "RokuMobile/12.6.0 (iOS; iPhone; 15.8.2)"
    }
    
    print(f"🌐 Getting challenge from: {url}")
    
    try:
        response = requests.get(url, headers=headers, timeout=10)
        print(f"📡 Challenge response: {response.status_code}")
        
        if response.status_code == 200:
            challenge_data = response.text
            print(f"📋 Challenge data: {challenge_data}")
            challenge_data = json.loads(challenge_data)
            challenge = challenge_data.get('data').get('challenge')
            print(f"✅ Received challenge: {challenge[:20]}...")
            return challenge
        else:
            print(f"❌ Challenge request failed: {response.text}")
            return None
            
    except Exception as e:
        print(f"❌ Error getting challenge: {e}")
        return None

def register_device(device_state: RokuDeviceState, challenge: str) -> bool:
    """Register device with Roku server"""
    url = f"https://auth.prod.mobile.roku.com/client/{device_state.client_id}/register"
    
    # Generate attestation result (integrity token)
    attestation_result = generate_attestation_result(challenge, device_state)
    
    # Prepare registration payload
    payload = {
        "challenge": challenge,
        "clientKey": device_state.public_key_der_b64,  # Base64 DER public key
        "attestationResult": attestation_result
    }
    
    headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "app": device_state.app_name,
        "os": device_state.os_name,
        "appversion": device_state.app_version,
        "User-Agent": "RokuMobile/12.6.0 (iOS; iPhone; 15.8.2)"
    }
    
    print(f"🌐 Registering device at: {url}")
    print(f"📤 Public key (first 50 chars): {device_state.public_key_der_b64[:50]}...")
    
    try:
        response = requests.post(url, json=payload, headers=headers, timeout=10)
        print(f"📡 Registration response: {response.status_code}")
        
        if response.status_code == 200:
            register_data = response.json()
            print(f"✅ Registration successful!")
            print(f"📋 Response: {register_data}")
            
            # Update device state with registration info
            device_state.last_challenge = challenge
            device_state.registration_token = register_data.get('token')
            device_state.token_expiration = register_data.get('expiration')
            
            # Save updated state
            with open("./roku-state.json", 'w') as f:
                json.dump(asdict(device_state), f, indent=2)
            
            return True
        else:
            print(f"❌ Registration failed: {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ Error during registration: {e}")
        return False

def sign_request_data(data: str, device_state: RokuDeviceState) -> str:
    """Sign request data using the private key (for future authenticated requests)"""
    # Load private key
    private_key = serialization.load_pem_private_key(
        device_state.private_key_pem.encode('utf-8'),
        password=None,
        backend=default_backend()
    )
    
    # Sign using RSA-SHA256 (matching ep.a.d() "SHA256withRSA")
    signature = private_key.sign(
        data.encode('utf-8'),
        padding.PKCS1v15(),
        hashes.SHA256()
    )
    
    return base64.b64encode(signature).decode('utf-8')

def make_identity_register_request(device_state: RokuDeviceState) -> bool:
    """Make the initial identity register request (first request in capture)"""
    url = "https://auth.prod.mobile.roku.com/identity/register"
    
    headers = {
        "x-roku-reserved-lat": "true",
        "x-roku-reserved-request-id": device_state.request_id,
        "x-roku-reserved-rida": "",
        "profile-id-is-uuid": "true",
        "x-roku-reserved-amoeba-ids": "",
        "x-roku-reserved-dev-id": device_state.device_id,
        "x-roku-reserved-profile-id": device_state.profile_id,
        "appversion": device_state.app_version,
        "x-roku-reserved-mobile-experiment-ids": "",
        "x-roku-reserved-channel-store-code": device_state.channel_store_code,
        "x-roku-reserved-client-id": device_state.client_id,
        "x-roku-reserved-culture-code": device_state.culture_code,
        "version": device_state.platform_version,
        "os": device_state.os_name,
        "x-roku-reserved-correlation": device_state.correlation_id,
        "x-roku-reserved-locale": device_state.locale,
        "x-roku-reserved-client-version": f"app=turing, appversion={device_state.app_version}, os={device_state.os_name}, platform=mobile, version={device_state.platform_version}",
        "x-roku-reserved-session-id": device_state.session_id,
        "osVersion": device_state.os_version,
        "Content-Type": "application/json",
        "x-roku-reserved-time-zone-offset": device_state.timezone_offset,
        "app": device_state.app_name,
        "User-Agent": "RokuMobile/12.6.0 (iOS; iPhone; 15.8.2)"
    }
    
    print(f"🌐 Making identity register request to: {url}")
    
    try:
        # Empty body as shown in capture
        response = requests.post(url, json={}, headers=headers, timeout=10)
        print(f"📡 Identity register response: {response.status_code}")
        
        if response.status_code in [200, 201, 202]:
            print(f"✅ Identity registration successful!")
            if response.text:
                print(f"📋 Response: {response.text}")
            return True
        else:
            print(f"❌ Identity registration failed: {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ Error during identity registration: {e}")
        return False

def main():
    """Main attestation flow"""
    print("🚀 Starting Roku Mobile Attestation Flow")
    print("=" * 50)
    
    # Step 1: Load or create device state
    device_state = load_or_create_device_state()
    
    print(f"\n📱 Device Info:")
    print(f"   Client ID: {device_state.client_id}")
    print(f"   Device ID: {device_state.device_id}")
    print(f"   Public Key: {device_state.public_key_der_b64[:50]}...")
    
    # Step 2: Make identity register request (first in capture)
    print(f"\n🔐 Step 1: Identity Registration")
    if not make_identity_register_request(device_state):
        print("❌ Identity registration failed, continuing anyway...")
    
    # Step 3: Get challenge
    print(f"\n🎯 Step 2: Getting Challenge")
    challenge = get_challenge(device_state)
    if not challenge:
        print("❌ Failed to get challenge, exiting")
        return
    
    # Step 4: Register device with challenge + public key
    print(f"\n📝 Step 3: Device Registration")
    if register_device(device_state, challenge):
        print("✅ Complete attestation flow successful!")
        
        # Demo: Sign a sample request
        print(f"\n🔏 Demo: Signing sample request data")
        sample_data = f"POST /api/sample challenge={challenge}"
        signature = sign_request_data(sample_data, device_state)
        print(f"   Data: {sample_data}")
        print(f"   Signature: {signature[:50]}...")
        
    else:
        print("❌ Device registration failed")

if __name__ == "__main__":
    main()