#!/usr/bin/env bash
#Declaración de variables

if ! [ "$(id -u)" = 0 ]; then
    echo "Debes ser root para ejecutarlo!" 
    exit
else
    echo "OK Has iniciado sesión como root" 
    sleep 2s
fi

cp bullseye-base.qcow2 /var/lib/libvirt/images/

echo "Vamos a comenzar creando un volumen "
sleep 2s
virsh -c qemu:///system vol-create-as default maquina1.qcow2 5G --format qcow2 --backing-vol bullseye-base.qcow2 --backing-vol-format qcow2

echo "Ahora procederemos a definir la red cargada en intra.xml"
sleep 2s
virsh -c qemu:///system net-define intra.xml
virsh net-start intra
echo "Ahora vamos a crear la máquina que nos permitirá cargar la imagen que hicimos "
sleep 2s

cp /var/lib/libvirt/images/maquina1.qcow2 /var/lib/libvirt/images/newmaquina1.qcow2

echo "Vamos a redimensionar el sistema de ficheros para su uso, tardará un momento"
virt-resize --expand /dev/sda1 /var/lib/libvirt/images/maquina1.qcow2 /var/lib/libvirt/images/newmaquina1.qcow2

mv /var/lib/libvirt/images/newmaquina1.qcow2 /var/lib/libvirt/images/maquina1.qcow2

sleep 2s

apt install virtinst -y > /dev/null 2>&1
virt-install --connect qemu:///system \
                         --virt-type kvm \
                         --name maquina1 \
                         --disk /var/lib/libvirt/images/maquina1.qcow2 \
                         --os-variant debian10 \
                         --network network=intra \
                         --memory 1024 \
                         --vcpus 2 \
                         --autoconsole none \
                         --import

sleep 20s
echo "Instalamos los paquetes que necesitaremos más adelante"
sleep 3s
ip=$(virsh domifaddr maquina1 | awk '{print $4}' | cut -d "/" -f 1 | sed -n 3p)
echo debian@$ip
ssh -i id_ecdsa -o "StrictHostKeyChecking no" debian@$ip sudo apt install apache2 lxc xfsprogs -y > /dev/null 2>&1


echo "Cambiamos el hostname a maquina1"
sleep 2s
ssh -i id_ecdsa debian@$ip sudo hostnamectl set-hostname maquina1

echo "Reiniciamos la máquina para aplicar los cambios"
ssh -i id_ecdsa debian@$ip sudo reboot

sleep 15s


echo "Copiamos y ajustamos permisos de /var/www"
scp -i id_ecdsa index.html debian@$ip:/home/debian
sleep 2s
ssh -i id_ecdsa debian@$ip sudo cp /home/debian/index.html /var/www/html/index.html
sleep 1s
ssh -i id_ecdsa debian@$ip sudo chown -R www-data:www-data /var/www

echo "ssh -i id_ecdsa debian@"$ip
echo "entra en la máquina para comprobar su funcionamiento, cuando termines pulsa enter"
read

sleep 4s
virsh -c qemu:///system attach-interface --domain maquina1 --type bridge --source br0 --model virtio --config --live
sleep 2s
echo "El bridge es el siguiente:"
ssh -i id_ecdsa debian@$ip ip a | egrep scope | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | sed -n 6p

virsh -c qemu:///system destroy maquina1

echo "Ajustamos los 2GB de RAM"
virsh -c qemu:///system setmaxmem maquina1 2097152 --config
sleep 1s
virsh -c qemu:///system setmem maquina1 2097152 --config
sleep 3s

echo "Encendemos la máquina"
virsh -c qemu:///system start maquina1
sleep 10s

echo "Creamos un volumen nuevo y lo enlazamos que será vdb"
sleep 3s
virsh -c qemu:///system vol-create-as default vol.raw --format raw 1G 
sleep 1s
virsh -c qemu:///system attach-disk maquina1 /var/lib/libvirt/images/vol.raw vdb --cache none --config
sleep 1s

echo "Ahora vamos a hacer que el volumen tenga formato xfs"
sleep 3s
ssh -i id_ecdsa debian@$ip sudo mkfs.xfs /dev/vdb
sleep 1s
ssh -i id_ecdsa debian@$ip sudo mount /dev/vdb /var/www/html


echo "Creamos el contenedor lxc"
sleep 15s
ssh -i id_ecdsa debian@$ip sudo lxc-create -n contenedor1 -t debian -- -r bullseye > /dev/null 2>&1

echo "Por último creamos un snapshot"
sleep 1s
virsh -c qemu:///system snapshot-create-as --domain maquina1 --name "snap-maquina1"
