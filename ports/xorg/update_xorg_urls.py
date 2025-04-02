import os
import re
import shutil
import subprocess
from urllib.request import urlopen
import json
import tempfile

def get_latest_nvidia_version():
    try:
        with urlopen("https://www.nvidia.com/object/unix.html") as response:
            html = response.read().decode('utf-8')
        # Look for the latest driver version in the HTML
        match = re.search(r'NVIDIA-Linux-x86_64-([\d.]+)\.run', html)
        if match:
            return match.group(1)
        return None
    except Exception as e:
        print(f"Error fetching NVIDIA version: {e}")
        return None

def update_repository(repo_path):
    try:
        if os.path.exists(repo_path):
            # Update existing repo
            subprocess.run(['git', '-C', repo_path, 'pull'], check=True)
        else:
            # Clone new repo
            subprocess.run(['git', 'clone', 'https://github.com/bfitzgit23/StormFS-Linux.git', repo_path], check=True)
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error updating repository: {e}")
        return False

def update_file_urls(file_path, nvidia_version):
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Update Xorg URLs
        xorg_pattern = re.compile(r'(https?://|ftp://)[^\s/]*\.(.*?)/pub/blfs/conglomeration/Xorg/')
        new_xorg_url = 'https://ftp2.osuosl.org/pub/blfs/conglomeration/Xorg/'
        new_content = xorg_pattern.sub(new_xorg_url, content)
        
        # Update NVIDIA URL if version is available
        if nvidia_version:
            nvidia_pattern = re.compile(r'http://us\.download\.nvidia\.com/XFree86/Linux-x86_64/[\d.]+/NVIDIA-Linux-x86_64-[\d.]+\.run')
            new_nvidia_url = f'http://us.download.nvidia.com/XFree86/Linux-x86_64/{nvidia_version}/NVIDIA-Linux-x86_64-{nvidia_version}.run'
            new_content = nvidia_pattern.sub(new_nvidia_url, new_content)
        
        if new_content != content:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(new_content)
            return True
        return False
    except Exception as e:
        print(f"Error processing {file_path}: {e}")
        return False

def process_repository(repo_path, nvidia_version):
    xorg_dir = os.path.join(repo_path, 'ports', 'xorg')
    if not os.path.exists(xorg_dir):
        print("Xorg directory not found in repository")
        return
    
    updated_files = 0
    for root, _, files in os.walk(xorg_dir):
        for file in files:
            file_path = os.path.join(root, file)
            try:
                if update_file_urls(file_path, nvidia_version):
                    print(f"Updated: {file_path}")
                    updated_files += 1
            except UnicodeDecodeError:
                continue
    
    print(f"\nTotal files updated: {updated_files}")

def main():
    # Create temporary directory for the repository
    with tempfile.TemporaryDirectory() as temp_dir:
        repo_path = os.path.join(temp_dir, 'StormFS-Linux')
        
        print("Fetching latest NVIDIA driver version...")
        nvidia_version = get_latest_nvidia_version()
        if nvidia_version:
            print(f"Found NVIDIA driver version: {nvidia_version}")
        else:
            print("Could not determine latest NVIDIA version, will only update Xorg URLs")
        
        print("\nCloning/updating repository...")
        if not update_repository(repo_path):
            return
        
        print("\nUpdating URLs in repository files...")
        process_repository(repo_path, nvidia_version)
        
        print("\nOperation complete. The repository with updated URLs is at:")
        print(repo_path)

if __name__ == "__main__":
    main()
