# TensorCash di Lightning AI Studio

Runner ini menjalankan image resmi LuckyPool TensorCash di sebuah container
Docker background pada mesin GPU Lightning AI Studio.

## Kebutuhan

- Studio Ubuntu/Linux dengan satu GPU NVIDIA aktif
- GPU compute capability `sm_80` atau lebih baru
- VRAM minimal 22.000 MiB (kelas 24 GB atau lebih besar)
- Docker daemon dengan NVIDIA Container Toolkit
- Shared memory minimal 4 GB; runner memakai 8 GB
- Ruang disk yang cukup untuk image dan model/cache

Studio dan mesin GPU harus tetap menyala. Menutup tampilan log tidak mematikan
miner, tetapi menghentikan Studio/instance akan menghentikan proses GPU.

## Jalankan langsung dari GitHub

Di terminal Lightning Studio, jalankan:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/zaimku/tsc-light/main/tsc-light.sh) run
```

Perintah tersebut memakai default berikut:

- Wallet: `tc1qrgmh0f6hg2c86ep53lynf8afk9f25ynvpamcr6`
- Worker: `lightning-<hostname>`
- Pool: `stratum+tls://sg.lproute.com:4160`
- Image: `luckypoolio/lpminer-tensorcash:1.1.5`
- GPU: index `0`

Unduhan pertama cukup besar. Tunggu sampai log menampilkan GPU terpilih,
backend siap, nilai `proof/s`, lalu accepted share/proof. Tekan `Ctrl+C` untuk
keluar dari tampilan log; container miner tetap berjalan.

## Clone repo (lebih mudah untuk kontrol)

```bash
git clone https://github.com/zaimku/tsc-light.git
cd tsc-light
chmod +x tsc-light.sh
./tsc-light.sh run
```

Jika repo sudah pernah di-clone:

```bash
cd ~/tsc-light
git pull --ff-only
./tsc-light.sh run
```

## Kontrol miner

Setelah clone repo, perintah yang tersedia adalah:

```bash
./tsc-light.sh status
./tsc-light.sh logs
./tsc-light.sh stop
./tsc-light.sh restart
./tsc-light.sh check
```

Perintah `stop` tidak menghapus volume Docker berisi model/cache, sehingga
startup berikutnya tidak perlu membuat cache dari nol. Container memakai
restart policy `unless-stopped`.

Jika tidak melakukan clone dan selalu memakai panggilan raw GitHub, kontrolnya:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/zaimku/tsc-light/main/tsc-light.sh) status
bash <(curl -fsSL https://raw.githubusercontent.com/zaimku/tsc-light/main/tsc-light.sh) logs
bash <(curl -fsSL https://raw.githubusercontent.com/zaimku/tsc-light/main/tsc-light.sh) stop
```

## Ganti pool, worker, wallet, atau GPU

Nilai dapat diberikan sebelum perintah:

```bash
POOL=stratum+tls://us-east.lproute.com:4160 \
WORKER=lightning-l4 \
GPU_INDEX=0 \
./tsc-light.sh restart
```

Untuk wallet lain:

```bash
WALLET=tc1_ALAMAT_ANDA ./tsc-light.sh restart
```

Pool LuckyPool yang dapat dipilih antara lain:

- Singapura: `stratum+tls://sg.lproute.com:4160`
- Hong Kong: `stratum+tls://hk.lproute.com:4160`
- Jepang: `stratum+tls://jp.lproute.com:4160`
- US East: `stratum+tls://us-east.lproute.com:4160`
- US West: `stratum+tls://us-west.lproute.com:4160`
- Eropa: `stratum+tls://eu.lproute.com:4160`

Pilih lokasi berdasarkan region mesin Lightning, bukan lokasi komputer lokal.

Dashboard pool: <https://tensorcash.luckypool.io/>

## Troubleshooting singkat

Jika `Docker tidak ditemukan` atau daemon tidak dapat diakses, gunakan image
Studio yang sudah menyediakan Docker dan NVIDIA runtime. Runner tidak memasang
atau mengubah driver GPU secara otomatis.

Jika container langsung berhenti:

```bash
./tsc-light.sh logs
```

Jika GPU ditolak, periksa VRAM dan compute capability:

```bash
nvidia-smi --query-gpu=index,name,memory.total,compute_cap --format=csv
```

Image miner mensyaratkan setidaknya 22.000 MiB VRAM; GPU 16 GB tidak cukup.
