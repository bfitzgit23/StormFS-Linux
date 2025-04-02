import os
import re
import subprocess
from urllib.request import urlopen
import shutil

def get_latest_nvidia_version():
    try:
        with urlopen("https://www.nvidia.com/object/unix.html") as response:
            html = response.read().decode('utf-8')
        match = re.search(r'NVIDIA-Linux-x86_64-([\d.]+)\.run', html)
        return match.group(1) if match else None
    except Exception as e:
        print(f"Error fetching NVIDIA version: {e}")
        return None

def update_repository(repo_path):
    try:
        if os.path.exists(repo_path):
            subprocess.run(['git', '-C', repo_path, 'pull'], check=True)
            print(f"Updated existing repository at {repo_path}")
        else:
            os.makedirs(os.path.dirname(repo_path), exist_ok=True)
            subprocess.run(['git', 'clone', 
                          'https://github.com/bfitzgit23/StormFS-Linux.git', 
                          repo_path], check=True)
            print(f"Cloned new repository to {repo_path}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error updating repository at {repo_path}: {e}")
        return False

def sync_repositories(source_path, dest_path):
    try:
        if os.path.exists(dest_path):
            shutil.rmtree(dest_path)
        shutil.copytree(source_path, dest_path)
        print(f"Synced repository from {source_path} to {dest_path}")
        return True
    except Exception as e:
        print(f"Error syncing repository to {dest_path}: {e}")
        return False

def update_file_urls(file_path, nvidia_version):
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        updated = False
        
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
        return 0
    
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
    
    return updated_files

def main():
    # Define repository paths
    primary_repo = '/StormFS/repos/xorg'
    secondary_repo = '/usr/ports/xorg'
    
    print("Fetching latest NVIDIA driver version...")
    nvidia_version = get_latest_nvidia_version()
    if nvidia_version:
        print(f"Found NVIDIA driver version: {nvidia_version}")
    else:
        print("Could not determine latest NVIDIA version, will only update Xorg URLs")
    
    print("\nUpdating primary repository...")
    if not update_repository(primary_repo):
        print("Failed to update primary repository, aborting")
        return
    
    print("\nUpdating URLs in primary repository...")
    updated_files = process_repository(primary_repo, nvidia_version)
    print(f"\nUpdated {updated_files} files in primary repository")
    
    print("\nSyncing to secondary repository location...")
    if not sync_repositories(primary_repo, secondary_repo):
        print("Failed to sync to secondary location")
    else:
        print(f"Successfully updated both repositories:")
        print(f"1. {primary_repo}")
        print(f"2. {secondary_repo}")

if __name__ == "__main__":
    main()
