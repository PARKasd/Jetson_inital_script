sudo nmcli device wifi connect MIRU_5G password miru0110

sudo apt install screen -y <br>
wget https://raw.githubusercontent.com/PARKasd/Jetson_inital_script/refs/heads/main/run.sh <br>
chmod +x run.sh <br>
screen ./run.sh



wget https://raw.githubusercontent.com/PARKasd/Jetson_inital_script/refs/heads/main/zshtobash.sh && chmod +x zshtobash.sh && screen ./zshtobash.sh

wget https://raw.githubusercontent.com/PARKasd/Jetson_inital_script/refs/heads/main/final.sh && chmod +x final.sh && screen ./final.sh
