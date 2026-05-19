import httpx
import random
import sys

BASE_URL = "https://suiflow1.vercel.app"

def test_vercel():
    print(f"=== TESTING VERCEL DEPLOYMENT: {BASE_URL} ===")
    
    client = httpx.Client(timeout=30.0)

    # 1. Test Root
    print("\n1. Testing Root Endpoint...")
    try:
        r = client.get(f"{BASE_URL}/")
        print(f"Status: {r.status_code}")
        print(f"Response: {r.json()}")
        if r.status_code != 200:
            print("FAILED: Root endpoint returned non-200 status")
            sys.exit(1)
    except Exception as e:
        print(f"FAILED: Connection error: {e}")
        sys.exit(1)
        
    # Generate unique credentials for registration
    suffix = random.randint(1000, 9999)
    phone = f"+155555{suffix}"
    username = f"user_{suffix}"
    password = "secure_test_password"
    full_name = f"Vercel Test User {suffix}"
    
    # 2. Test Registration
    print(f"\n2. Testing Registration for {username} ({phone})...")
    try:
        r = client.post(f"{BASE_URL}/api/auth/register", json={
            "phone_number": phone,
            "username": username,
            "password": password,
            "full_name": full_name
        })
        print(f"Status: {r.status_code}")
        print(f"Response: {r.text}")
        if r.status_code != 200:
            print("FAILED: Registration endpoint failed")
            sys.exit(1)
        data = r.json()
        wallet_address = data["user"]["wallet"]["address"]
        print(f"Registered successfully! Wallet address: {wallet_address}")
    except Exception as e:
        print(f"FAILED: Registration request failed: {e}")
        sys.exit(1)
        
    # 3. Test Login
    print(f"\n3. Testing Login...")
    try:
        # FastAPI Form parameters for OAuth2 username/password flow
        r = client.post(f"{BASE_URL}/api/auth/login", data={
            "username": phone,
            "password": password
        })
        print(f"Status: {r.status_code}")
        if r.status_code != 200:
            print(f"FAILED: Login failed: {r.text}")
            sys.exit(1)
        token_data = r.json()
        access_token = token_data["token"]["access_token"]
        print("Logged in successfully! Token obtained.")
    except Exception as e:
        print(f"FAILED: Login request failed: {e}")
        sys.exit(1)
        
    # 4. Test User Lookup
    print(f"\n4. Testing User Lookup for {username}...")
    try:
        r = client.get(f"{BASE_URL}/api/auth/lookup?query={username}")
        print(f"Status: {r.status_code}")
        print(f"Response: {r.json()}")
        if r.status_code != 200:
            print("FAILED: Lookup failed")
            sys.exit(1)
    except Exception as e:
        print(f"FAILED: Lookup request failed: {e}")
        sys.exit(1)
        
    # 5. Test Create Vault
    print(f"\n5. Testing Create Vault...")
    try:
        headers = {"Authorization": f"Bearer {access_token}"}
        r = client.post(f"{BASE_URL}/api/vaults/", json={"name": "Vercel Savings Vault"}, headers=headers)
        print(f"Status: {r.status_code}")
        print(f"Response: {r.json()}")
        if r.status_code != 200:
            print("FAILED: Vault creation failed")
            sys.exit(1)
        print("Vault created successfully on Vercel deployment!")
    except Exception as e:
        print(f"FAILED: Vault creation request failed: {e}")
        sys.exit(1)
        
    print("\n=== ALL VERCEL DEPLOYMENT HTTP TESTS PASSED SUCCESSFULLY! ===")

if __name__ == "__main__":
    test_vercel()
