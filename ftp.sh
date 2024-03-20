#!/bin/bash

# Function to display loading animation
function loading_animation() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    local i=0
    while ps -p $pid > /dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
        ((i++))
    done
    printf "    \b\b\b\b"
}

# Function to check if a command is available
function command_exists() {
    command -v "$1" > /dev/null 2>&1
}

# Function to enable and start vsftpd service
function enable_start_vsftpd() {
    systemctl enable --now vsftpd
    whiptail --msgbox "vsftpd service has been enabled and started!" 10 50
}

# Function to allow ports through UFW
function allow_ports_ufw() {
    sudo ufw allow 20/tcp
    sudo ufw allow 21/tcp
    sudo ufw allow 990/tcp
    sudo ufw allow 5000:10000/tcp
    whiptail --msgbox "Ports have been allowed through UFW!" 10 50
}

# Function to create an FTP user using whiptail
function create_ftp_user_whiptail() {
    while true; do
        local username
        local password
        local full_name
        local room_number
        local work_phone
        local home_phone
        local other_info

        # Prompt the user for the FTP username
        username=$(whiptail --inputbox "Enter FTP username:" 10 50 3>&1 1>&2 2>&3)
        exitstatus=$?
        if [ $exitstatus -ne 0 ]; then
            whiptail --msgbox "User creation aborted. No changes were made." 10 50
            return 1
        fi

        # Check if the user already exists
        if id "$username" &>/dev/null; then
            if ! whiptail --yesno "Error: User $username already exists. Do you want to input another username?" 10 50; then
                whiptail --msgbox "User creation aborted. No changes were made." 10 50
                return 1
            fi
        else
            # Proceed to user creation if the user doesn't exist

            # Prompt the user for the password
            password=$(whiptail --passwordbox "Enter password for user $username:" 10 50 3>&1 1>&2 2>&3)
            exitstatus=$?
            if [ $exitstatus -ne 0 ]; then
                whiptail --msgbox "User creation aborted. No changes were made." 10 50
                return 1
            fi

            # Prompt the user for additional information
            full_name=$(whiptail --inputbox "Full Name:" 10 50 3>&1 1>&2 2>&3)
            room_number=$(whiptail --inputbox "Room Number:" 10 50 3>&1 1>&2 2>&3)
            work_phone=$(whiptail --inputbox "Work Phone:" 10 50 3>&1 1>&2 2>&3)
            home_phone=$(whiptail --inputbox "Home Phone:" 10 50 3>&1 1>&2 2>&3)
            other_info=$(whiptail --inputbox "Other:" 10 50 3>&1 1>&2 2>&3)

            # Create the user
            useradd -m -G users -p "$(echo "$password" | openssl passwd -1 -stdin)" -c "$full_name, $room_number, $work_phone, $home_phone, $other_info" "$username"

            # Check if user creation was successful
            if [ $? -eq 0 ]; then
                whiptail --msgbox "User $username has been successfully created!" 10 50
                echo -e "\e[32mUser $username has been successfully created!\e[0m"  # Green color

            else
                whiptail --msgbox "Error: User creation failed. No changes were made." 10 50
                echo -e "\e[31mError: User creation failed. No changes were made.\e[0m"  # Red color
                return 1
            fi

            # Ask if the user wants to create another FTP user
            if ! whiptail --yesno "Do you want to create another FTP user?" 10 50; then

                create_ftp_folder_and_chown
                configure_vsftpd
                generate_ssl_certificate
                update_vsftpd_configuration
                restart_vsftpd_service

                return 0  # Exit the loop if the user doesn't want to create another user
            fi
        fi
    done
}

function create_ftp_folder_and_chown() {

    # Check if /ftp folder exists
    if [ -d "/ftp" ]; then
        whiptail --yesno "The /ftp folder already exists. Do you want to delete it and proceed?" 10 50 || return 1
        sudo rm -r /ftp
    fi

    whiptail --msgbox "/ftp folder will be created!" 10 50
    sudo mkdir /ftp

    while true; do
        local admin_username
        local chroot_list="/etc/vsftpd.chroot_list"
        admin_username=$(whiptail --inputbox "Enter the username of the admin user:" 10 50 3>&1 1>&2 2>&3)
        exitstatus=$?
        
        if [ $exitstatus -ne 0 ]; then
            whiptail --msgbox "Admin user assignment aborted. No changes were made." 10 50
            return 1
        fi

        if id "$admin_username" &>/dev/null; then
            chown "$admin_username" /ftp

            # Create vsftpd.chroot_list file
            sudo touch "$chroot_list"

            # Add admin username to vsftpd.chroot_list
            echo "$admin_username" | sudo tee -a "$chroot_list" > /dev/null

            whiptail --msgbox "/ftp folder has been created and assigned to $admin_username!" 10 50
            whiptail --msgbox "$admin_username has been added to the chroot_list" 10 50

            return 0
        else
            whiptail --yesno "Error: User $admin_username does not exist. Do you want to input another username?" 10 50 || return 1
        fi
    done
}

# Function to configure and secure vsftpd
function configure_vsftpd() {

    whiptail --msgbox "vsftpd will be configured and secured." 10 50

    echo "the following lines have been added to /etc/vsftpd.conf"

    # Ensure necessary lines are uncommented
    sudo sed -i 's/#\?anonymous_enable=.*/anonymous_enable=NO/' /etc/vsftpd.conf
    sudo sed -i 's/#\?local_enable=.*/local_enable=YES/' /etc/vsftpd.conf
    sudo sed -i 's/#\?write_enable=.*/write_enable=YES/' /etc/vsftpd.conf

    # Add passive mode port configuration
    echo "pasv_min_port=5000" | sudo tee -a /etc/vsftpd.conf
    echo "pasv_max_port=10000" | sudo tee -a /etc/vsftpd.conf

    # Specify default directory
    echo "local_root=/ftp" | sudo tee -a /etc/vsftpd.conf

    # Enable chroot for local users
    sudo sed -i 's/#\?chroot_local_user=.*/chroot_local_user=YES/' /etc/vsftpd.conf
    sudo sed -i 's/#\?chroot_list_enable=.*/chroot_list_enable=YES/' /etc/vsftpd.conf
    sudo sed -i 's/#\?chroot_list_file=.*/chroot_list_file=YES/' /etc/vsftpd.conf

    # Add additional line
    echo "allow_writeable_chroot=YES" | sudo tee -a /etc/vsftpd.conf

    # Set file permissions
    echo "local_umask=0002" | sudo tee -a /etc/vsftpd.conf

    # Restart vsftpd service
    sudo systemctl restart --now vsftpd

    whiptail --msgbox "vsftpd has been configured and secured." 10 50
}

# Function to generate ssl certificate
function generate_ssl_certificate() {
    local country
    local state
    local locality
    local organization
    local organizational_unit
    local common_name
    local email

    # Gather SSL certificate information using whiptail
    country=$(whiptail --inputbox "Enter Country Name (2 letter code):" 10 50 3>&1 1>&2 2>&3)
    state=$(whiptail --inputbox "Enter State or Province Name (full name):" 10 50 3>&1 1>&2 2>&3)
    locality=$(whiptail --inputbox "Enter Locality Name (eg, city):" 10 50 3>&1 1>&2 2>&3)
    organization=$(whiptail --inputbox "Enter Organization Name (eg, company):" 10 50 3>&1 1>&2 2>&3)
    organizational_unit=$(whiptail --inputbox "Enter Organizational Unit Name (eg, section):" 10 50 3>&1 1>&2 2>&3)
    common_name=$(whiptail --inputbox "Enter Common Name (e.g. server FQDN or YOUR name):" 10 50 3>&1 1>&2 2>&3)
    email=$(whiptail --inputbox "Enter Email Address:" 10 50 3>&1 1>&2 2>&3)

    # Generate SSL certificate with the provided information
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/vsftpd.pem -out /etc/ssl/private/vsftpd.pem \
        -subj "/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizational_unit/CN=$common_name/emailAddress=$email"

    whiptail --msgbox "SSL certificate has been generated." 10 50
}

# Function to configure vsftpd using ssl
function update_vsftpd_configuration() {
    local vsftpd_conf="/etc/vsftpd.conf"

    # Remove existing SSL configuration lines
    sudo sed -i '/^rsa_cert_file=/d' "$vsftpd_conf"
    sudo sed -i '/^rsa_private_key_file=/d' "$vsftpd_conf"
    sudo sed -i '/^ssl_enable=/d' "$vsftpd_conf"

    # Add new SSL configuration lines
    echo "rsa_cert_file=/etc/ssl/private/vsftpd.pem" | sudo tee -a "$vsftpd_conf"
    echo "rsa_private_key_file=/etc/ssl/private/vsftpd.pem" | sudo tee -a "$vsftpd_conf"
    echo "ssl_enable=YES" | sudo tee -a "$vsftpd_conf"
    echo "allow_anon_ssl=NO" | sudo tee -a "$vsftpd_conf"
    echo "force_local_data_ssl=YES" | sudo tee -a "$vsftpd_conf"
    echo "force_local_logins_ssl=YES" | sudo tee -a "$vsftpd_conf"
    echo "ssl_tlsv1=YES" | sudo tee -a "$vsftpd_conf"
    echo "ssl_sslv2=NO" | sudo tee -a "$vsftpd_conf"
    echo "ssl_sslv3=NO" | sudo tee -a "$vsftpd_conf"
    echo "require_ssl_reuse=NO" | sudo tee -a "$vsftpd_conf"
    echo "ssl_ciphers=HIGH" | sudo tee -a "$vsftpd_conf"

    whiptail --msgbox "vsftpd configuration has been updated for SSL/TLS." 10 50
}

# Function to restart vsftpd service
function restart_vsftpd_service() {
    sudo systemctl restart --now vsftpd
    whiptail --msgbox "vsftpd service has been restarted." 10 50
}

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Check if whiptail is installed, if not, install it
if ! command_exists "whiptail"; then
    echo "Installing whiptail..."
    apt-get update
    apt-get install -y whiptail > /dev/null 2>&1
fi

# Check if vsftpd is installed
if command_exists "vsftpd"; then
    # Ask the user if they want to enable and start the vsftpd service
    if whiptail --yesno "vsftpd is already installed. Do you want to enable and start the vsftpd service?" 10 50; then
        enable_start_vsftpd
    else
        whiptail --msgbox "You can manually enable and start the vsftpd service using 'sudo systemctl enable --now vsftpd'" 10 50
    fi

    # Ask the user if they want to allow ports through UFW
    if whiptail --yesno "Do you want to allow ports through UFW?" 10 50; then
        allow_ports_ufw
    else
        whiptail --msgbox "You can manually allow ports through UFW using the appropriate commands." 10 50
    fi

    # Call the function to create an FTP user using whiptail
    if whiptail --yesno "Do you want to create an FTP user?" 10 50; then
        create_ftp_user_whiptail
    else
            whiptail --msgbox "FTP user creation skipped. You can manually create an FTP user using the appropriate commands." 10 50

            create_ftp_folder_and_chown
            configure_vsftpd
            generate_ssl_certificate
            update_vsftpd_configuration
            restart_vsftpd_service
    fi

else
    # Display welcome message
    whiptail --msgbox "An FTP server (vsftpd) will be installed and configured on your system." 10 50

    # Confirm installation with the user
    if whiptail --yesno "Do you want to install the package vsftpd?" 10 50; then
        # Install vsftpd in the background
        apt-get update
        apt-get install -y vsftpd > /dev/null 2>&1 &

        # Display loading animation
        loading_animation $!

        # Check if installation was successful
        if [ $? -eq 0 ]; then
            whiptail --msgbox "vsftpd has been successfully installed!" 10 50

            # Ask the user if they want to enable and start the vsftpd service
            if whiptail --yesno "Do you want to enable and start the vsftpd service?" 10 50; then
                enable_start_vsftpd
            else
                whiptail --msgbox "You can manually enable and start the vsftpd service using 'sudo systemctl enable --now vsftpd'" 10 50
            fi

            # Ask the user if they want to allow ports through UFW
            if whiptail --yesno "Do you want to allow ports through UFW?" 10 50; then
                allow_ports_ufw
            else
                whiptail --msgbox "You can manually allow ports through UFW using the appropriate commands." 10 50
            fi

            # Call the function to create an FTP user using whiptail
            if whiptail --yesno "Do you want to create an FTP user?" 10 50; then
                create_ftp_user_whiptail
            else
                    whiptail --msgbox "FTP user creation skipped. You can manually create an FTP user using the appropriate commands." 10 50

                    create_ftp_folder_and_chown
                    configure_vsftpd
                    generate_ssl_certificate
                    update_vsftpd_configuration
                    restart_vsftpd_service
            fi

        else
            whiptail --msgbox "Installation failed. Please check the logs for more information." 10 50
        fi
    else
        whiptail --msgbox "Installation aborted. No changes were made." 10 50
    fi
fi