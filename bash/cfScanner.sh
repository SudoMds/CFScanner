#!/usr/bin/env python3
import subprocess
import sys
import os
import argparse
import logging
import time

# Constants for configuration and IP files
CONFIG_FILE = 'settings.txt'
IP_FILE = 'ips.txt'

# Configure logging
logging.basicConfig(
    filename='cloudflare_updater.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

def install_requirements(requirements_file):
    """
    Install packages from a requirements file.
    
    Args:
        requirements_file (str): Path to the requirements file.
    """
    try:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-r", requirements_file])
        logging.info("Requirements installed successfully from %s.", requirements_file)
    except subprocess.CalledProcessError as e:
        logging.error("Failed to install requirements from %s: %s", requirements_file, e)
        sys.exit(1)

# Check if dependencies are installed
try:
    import CloudFlare
except ImportError:
    print("Installing packages from requirements.txt...")
    logging.info("CloudFlare module not found. Installing dependencies.")
    install_requirements("requirements.txt")
    try:
        import CloudFlare
    except ImportError:
        logging.error("Failed to import CloudFlare after installation.")
        sys.exit(1)

def print_header():
    """
    Print a beautiful header to the console and log the action.
    """
    header = """
====================================================
         Cloudflare DNS Updater by MDS
====================================================
    """
    print(header)
    logging.info("Header printed.")

def init_settings():
    """
    Initialize settings and save them to the configuration file.
    
    Allows users to input Cloudflare credentials and zone information.
    Supports command-line arguments for automation.
    """
    print_header()
    
    parser = argparse.ArgumentParser(description="Initialize Cloudflare DNS Updater Settings")
    parser.add_argument('--email', help='Cloudflare login email')
    parser.add_argument('--api_key', help='Cloudflare global API key')
    parser.add_argument('--zone', help='Cloudflare zone name (e.g., mydomain.com)')
    parser.add_argument('--subdomain', help='Base subdomain to use (e.g., subdomain.mydomain.com)')
    args, unknown = parser.parse_known_args()

    # Prompt for inputs if not provided via arguments
    email = args.email or input("Enter your Cloudflare login email: ").strip()
    api_key = args.api_key or input("Enter your Cloudflare global API key: ").strip()
    zone = args.zone or input("Enter your Cloudflare zone name (e.g., mydomain.com): ").strip()
    subdomain = args.subdomain or input("Enter the base subdomain to use (e.g., subdomain.mydomain.com): ").strip()

    # Initialize Cloudflare API client to fetch the zone_id
    try:
        cf = CloudFlare.CloudFlare(email=email, token=api_key)
        zones = cf.zones.get(params={"name": zone})
        if not zones:
            print(f"Could not find Cloudflare zone '{zone}'. Please check the domain.")
            logging.error("Cloudflare zone '%s' not found.", zone)
            sys.exit(1)
        zone_id = zones[0]["id"]
        logging.info("Retrieved zone ID '%s' for zone '%s'.", zone_id, zone)
    except CloudFlare.exceptions.CloudFlareAPIError as e:
        print(f"Failed to retrieve zone ID: {e}")
        logging.error("Cloudflare API error while retrieving zone ID: %s", e)
        sys.exit(1)

    # Save settings to file
    try:
        with open(CONFIG_FILE, 'w') as f:
            f.write(f"email={email}\n")
            f.write(f"api_key={api_key}\n")
            f.write(f"zone_id={zone_id}\n")
            f.write(f"zone={zone}\n")
            f.write(f"subdomain={subdomain}\n")
        # Secure the configuration file by setting file permissions (Unix-based systems)
        if os.name == 'posix':
            os.chmod(CONFIG_FILE, 0o600)
        print(f"Settings initialized and saved to '{CONFIG_FILE}'.")
        logging.info("Settings saved to '%s'.", CONFIG_FILE)
    except IOError as e:
        print(f"Failed to write settings to '{CONFIG_FILE}': {e}")
        logging.error("IOError while writing settings: %s", e)
        sys.exit(1)

def read_settings():
    """
    Read settings from the configuration file.
    
    Returns:
        dict: A dictionary containing the settings.
    """
    if not os.path.exists(CONFIG_FILE):
        print(f"Configuration file '{CONFIG_FILE}' not found. Please initialize settings first using 'iscript'.")
        logging.error("Configuration file '%s' not found.", CONFIG_FILE)
        sys.exit(1)

    settings = {}
    try:
        with open(CONFIG_FILE, 'r') as f:
            for line in f:
                key, value = line.strip().split('=', 1)
                settings[key] = value
        logging.info("Settings read successfully from '%s'.", CONFIG_FILE)
    except Exception as e:
        print(f"Error reading configuration: {e}")
        logging.error("Error reading configuration from '%s': %s", CONFIG_FILE, e)
        sys.exit(1)
    return settings

def read_ips_from_file():
    """
    Read IP addresses from the IP file.
    
    Returns:
        list: A list of IP addresses.
    """
    if not os.path.exists(IP_FILE):
        print(f"IP file '{IP_FILE}' not found.")
        logging.error("IP file '%s' not found.", IP_FILE)
        sys.exit(1)

    try:
        with open(IP_FILE, 'r') as file:
            ips = [line.strip() for line in file if line.strip()]
        logging.info("Read %d IP address(es) from '%s'.", len(ips), IP_FILE)
    except Exception as e:
        print(f"Error reading IP file: {e}")
        logging.error("Error reading IP file '%s': %s", IP_FILE, e)
        sys.exit(1)

    if not ips:
        print("No IP addresses found in the IP file.")
        logging.warning("No IP addresses found in '%s'.", IP_FILE)
        sys.exit(1)

    return ips

def create_or_update_records():
    """
    Create or update A records for each IP address using the Cloudflare API.
    Also deletes any existing A records not present in the current IP list.
    """
    print_header()
    logging.info("Starting DNS A records creation/update process.")

    settings = read_settings()
    
    try:
        cf = CloudFlare.CloudFlare(email=settings['email'], token=settings['api_key'])
        logging.info("Initialized Cloudflare API client.")
    except CloudFlare.exceptions.CloudFlareAPIError as e:
        print(f"Failed to initialize Cloudflare API client: {e}")
        logging.error("Cloudflare API client initialization failed: %s", e)
        sys.exit(1)

    zone_id = settings['zone_id']
    base_subdomain = settings['subdomain']

    desired_ips = read_ips_from_file()
    num_ips = len(desired_ips)
    print(f"Found {num_ips} IP address(es) in '{IP_FILE}'.")
    logging.info("Processing %d IP address(es).", num_ips)

    # Fetch existing DNS records for the subdomain
    try:
        existing_records = cf.zones.dns_records.get(
            zone_id, 
            params={"name": base_subdomain, "type": "A"}
        )
        existing_ips = {record['content']: record['id'] for record in existing_records}
        logging.info("Fetched existing DNS A records for '%s'.", base_subdomain)
    except CloudFlare.exceptions.CloudFlareAPIError as e:
        print(f"Error fetching existing DNS records: {e}")
        logging.error("Error fetching existing DNS records: %s", e)
        sys.exit(1)

    desired_ips_set = set(desired_ips)
    existing_ips_set = set(existing_ips.keys())

    # Determine records to create, keep, or delete
    ips_to_create = desired_ips_set - existing_ips_set
    ips_to_delete = existing_ips_set - desired_ips_set
    ips_to_keep = desired_ips_set & existing_ips_set

    # Create new A records
    for ip_address in ips_to_create:
        print(f"Creating A record for '{base_subdomain}' with IP '{ip_address}'...")
        logging.info("Creating A record: %s -> %s", base_subdomain, ip_address)

        a_record = {
            "type": "A",
            "name": base_subdomain,
            "ttl": 60,  # TTL of 1 minute
            "content": ip_address,
            "proxied": False  # Set to True if you want Cloudflare's proxy features
        }

        try:
            cf.zones.dns_records.post(zone_id, data=a_record)
            print(f"Successfully created A record: {base_subdomain} -> {ip_address}")
            logging.info("Successfully created A record: %s -> %s", base_subdomain, ip_address)
            time.sleep(0.2)  # Sleep for 200ms to respect rate limits
        except CloudFlare.exceptions.CloudFlareAPIError as e:
            print(f"Error creating A record for '{base_subdomain}': {e}")
            logging.error("Error creating A record for '%s': %s", base_subdomain, e)

    # Delete obsolete A records
    for ip_address in ips_to_delete:
        record_id = existing_records[[rec['content'] for rec in existing_records].index(ip_address)]['id']
        print(f"Deleting obsolete A record for '{base_subdomain}' with IP '{ip_address}'...")
        logging.info("Deleting A record: %s -> %s", base_subdomain, ip_address)
        try:
            cf.zones.dns_records.delete(zone_id, record_id)
            print(f"Successfully deleted A record: {base_subdomain} -> {ip_address}")
            logging.info("Successfully deleted A record: %s -> %s", base_subdomain, ip_address)
            time.sleep(0.2)  # Sleep for 200ms to respect rate limits
        except CloudFlare.exceptions.CloudFlareAPIError as e:
            print(f"Error deleting A record for '{base_subdomain}': {e}")
            logging.error("Error deleting A record for '%s': %s", base_subdomain, e)

    # Optionally, update TTL or proxied status for existing records (if needed)
    # Uncomment and modify the following section if you want to enforce specific TTL or proxied settings

    # for ip_address in ips_to_keep:
    #     record_id = existing_records[[rec['content'] for rec in existing_records].index(ip_address)]['id']
    #     updated_record = {
    #         "ttl": 60,
    #         "proxied": False
    #     }
    #     try:
    #         cf.zones.dns_records.put(zone_id, record_id, data=updated_record)
    #         logging.info("Updated A record settings for %s -> %s", base_subdomain, ip_address)
    #     except CloudFlare.exceptions.CloudFlareAPIError as e:
    #         print(f"Error updating A record for '{base_subdomain}': {e}")
    #         logging.error("Error updating A record for '%s': %s", base_subdomain, e)

    print("DNS A records update process completed.")
    logging.info("DNS A records update process completed.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Cloudflare DNS A Record Updater")
    parser.add_argument("action", choices=["iscript", "rscript"], help="Specify 'iscript' to initialize settings or 'rscript' to run the script")
    args = parser.parse_args()

    if args.action == "iscript":
        init_settings()
    elif args.action == "rscript":
        create_or_update_records()
