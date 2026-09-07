# Menjalankan TensorCash di Nosana

## Kondisi deployment PyTorch lama

Deployment template PyTorch menjalankan JupyterLab pada port 8888. Container
tersebut bukan miner. Jangan menjalankan `tsc-light.sh` di terminal Jupyter
karena skrip Lightning tersebut membutuhkan Docker, sedangkan workload Nosana
sendiri sudah berjalan di dalam container.

Gunakan image miner langsung sebagai job definition Nosana. Image tersebut
memiliki entrypoint, command, health check, model, dan miner bawaan sendiri.

## Mengganti deployment menjadi miner

1. Buka deployment Nosana yang sekarang.
2. Stop deployment agar container Jupyter Revision 1 dan biaya GPU berhenti.
3. Pilih edit job definition atau buat revision baru.
4. Hapus definisi PyTorch/Jupyter lama, lalu tempel seluruh isi
   [`nosana-job.json`](./nosana-job.json).
5. Simpan sebagai Revision 2 dan start deployment.
6. Buka bagian Logs. Endpoint port 8888 tidak akan ada lagi karena miner hanya
   membutuhkan koneksi TCP keluar ke pool.

Pengaturan deployment tetap dapat memakai:

- GPU market: NVIDIA RTX 4090 24 GB
- Strategy: `INFINITE`
- Timeout: 6 jam
- Replicas: 1

Strategi `INFINITE` membuat Nosana menjadwalkan job pengganti menjelang timeout.
Setiap container miner baru menggunakan konfigurasi wallet, worker, dan pool
yang sama dari job definition.

## Tanda miner berhasil

Pada Logs, tunggu pesan yang menunjukkan:

- GPU RTX 4090 terpilih dan profile `24gb`;
- model/backend selesai disiapkan;
- koneksi ke `sg.lproute.com:4160`;
- output `proof/s`;
- accepted share/proof.

Startup pertama dapat memerlukan beberapa menit. Status CPU 0% dan memori sekitar
0,1 GB seperti pada template Jupyter berarti miner belum berjalan.

## Mengubah konfigurasi

Nilai berikut berada di `global.env` pada `nosana-job.json`:

```json
"WALLET": "tc1qrgmh0f6hg2c86ep53lynf8afk9f25ynvpamcr6",
"LABEL": "nosana-4090",
"POOL": "stratum+tls://sg.lproute.com:4160"
```

Untuk region node di Amerika, pool dapat diganti menjadi:

```text
stratum+tls://us-east.lproute.com:4160
```

Untuk Eropa:

```text
stratum+tls://eu.lproute.com:4160
```

## Keamanan endpoint lama

Template Jupyter yang dipakai Revision 1 mengaktifkan terminal dan menonaktifkan
token/password. Siapa pun yang memperoleh URL endpoint dapat mencoba mengakses
workspace dan terminal. Stop Revision 1 setelah selesai dan jangan membagikan
URL endpoint tersebut.

## Referensi

- <https://docs.nosana.com/deployments/jobs/job-definition/schema.html>
- <https://docs.nosana.com/deployments/strategies.html>
- <https://docs.nosana.com/api/manage-deployments.html>
