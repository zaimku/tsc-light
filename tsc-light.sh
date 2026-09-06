#!/usr/bin/env bash
set -Eeuo pipefail

# TensorCash / LuckyPool runner for an Ubuntu-based Lightning AI Studio.
# The miner runs in a detached Docker container; closing `docker logs -f`
# does not stop it.

readonly DEFAULT_WALLET="tc1qrgmh0f6hg2c86ep53lynf8afk9f25ynvpamcr6"
readonly DEFAULT_POOL="stratum+tls://sg.lproute.com:4160"
readonly DEFAULT_IMAGE="luckypoolio/lpminer-tensorcash:1.1.5"
readonly RAW_SCRIPT_URL="https://raw.githubusercontent.com/zaimku/tsc-light/main/tsc-light.sh"

WALLET="${WALLET:-${DEFAULT_WALLET}}"
POOL="${POOL:-${DEFAULT_POOL}}"
WORKER="${WORKER:-lightning-$(hostname 2>/dev/null || printf 'studio')}"
IMAGE="${IMAGE:-${DEFAULT_IMAGE}}"
GPU_INDEX="${GPU_INDEX:-0}"
CONTAINER_NAME="${CONTAINER_NAME:-tensorcash-lightning}"
MODEL_VOLUME="${MODEL_VOLUME:-tensorcash-lightning-models}"
UPDATE_VOLUME="${UPDATE_VOLUME:-tensorcash-lightning-updates}"
SHM_SIZE="${SHM_SIZE:-8g}"

DOCKER=()

if [[ "${BASH_SOURCE[0]}" == /dev/fd/* || ! -f "${BASH_SOURCE[0]}" ]]; then
  CONTROL_COMMAND="bash <(curl -fsSL ${RAW_SCRIPT_URL})"
else
  CONTROL_COMMAND="./$(basename "${BASH_SOURCE[0]}")"
fi

info() {
  printf '[tsc-light] %s\n' "$*"
}

die() {
  printf '[tsc-light] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
TensorCash miner for Lightning AI Studio

Usage:
  ./tsc-light.sh run       Start in background, then follow logs (default)
  ./tsc-light.sh start     Start in background
  ./tsc-light.sh logs      Follow miner logs; Ctrl+C only closes the log view
  ./tsc-light.sh status    Show container and GPU status
  ./tsc-light.sh stop      Stop the miner container
  ./tsc-light.sh restart   Recreate and start the miner container
  ./tsc-light.sh check     Check host requirements without pulling the image
  ./tsc-light.sh help      Show this help

Optional environment variables:
  WALLET, POOL, WORKER, IMAGE, GPU_INDEX, SHM_SIZE, CONTAINER_NAME

Example with overrides:
  POOL=stratum+tls://us-east.lproute.com:4160 WORKER=lightning-l4 \
    ./tsc-light.sh run
EOF
}

detect_docker() {
  command -v docker >/dev/null 2>&1 ||
    die "Docker tidak ditemukan. Gunakan Lightning Studio berbasis Ubuntu yang mendukung Docker + NVIDIA runtime."

  if docker info >/dev/null 2>&1; then
    DOCKER=(docker)
  elif command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then
    DOCKER=(sudo docker)
  else
    die "Docker daemon tidak dapat diakses. Pastikan Docker aktif dan user memiliki akses ke daemon."
  fi
}

validate_settings() {
  [[ "${WALLET}" =~ ^(solo:)?tc1[[:alnum:]]+$ ]] ||
    die "WALLET harus berupa alamat tc1... atau solo:tc1..."
  [[ "${POOL}" =~ ^stratum\+(tcp|tls|ssl)://[^/:[:space:]]+:[0-9]+$ ]] ||
    die "POOL harus berbentuk stratum+tls://host:port"
  [[ "${GPU_INDEX}" =~ ^[0-9]+$ ]] || die "GPU_INDEX harus berupa angka 0 atau lebih."
  [[ "${CONTAINER_NAME}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]+$ ]] ||
    die "CONTAINER_NAME tidak valid."
}

check_gpu() {
  command -v nvidia-smi >/dev/null 2>&1 ||
    die "nvidia-smi tidak ditemukan. Pastikan Studio memakai mesin GPU."

  local gpu_line gpu_name memory_mib compute_cap compute_major
  gpu_line="$(nvidia-smi --id="${GPU_INDEX}" \
    --query-gpu=name,memory.total,compute_cap \
    --format=csv,noheader,nounits 2>/dev/null || true)"
  [[ -n "${gpu_line}" ]] || die "GPU index ${GPU_INDEX} tidak tersedia."

  IFS=',' read -r gpu_name memory_mib compute_cap <<<"${gpu_line}"
  gpu_name="${gpu_name#"${gpu_name%%[![:space:]]*}"}"
  gpu_name="${gpu_name%"${gpu_name##*[![:space:]]}"}"
  memory_mib="${memory_mib//[[:space:]]/}"
  compute_cap="${compute_cap//[[:space:]]/}"
  compute_major="${compute_cap%%.*}"

  [[ "${memory_mib}" =~ ^[0-9]+$ ]] || die "VRAM GPU tidak dapat dibaca: ${gpu_line}"
  [[ "${compute_major}" =~ ^[0-9]+$ ]] || die "Compute capability tidak dapat dibaca: ${gpu_line}"
  ((memory_mib >= 22000)) ||
    die "GPU ${gpu_name} hanya memiliki ${memory_mib} MiB; miner memerlukan minimal 22000 MiB VRAM."
  ((compute_major >= 8)) ||
    die "GPU ${gpu_name} memiliki compute capability ${compute_cap}; miner memerlukan sm_80 atau lebih baru."

  info "GPU: ${gpu_name} (${memory_mib} MiB, sm_${compute_cap/./})"
}

container_exists() {
  "${DOCKER[@]}" container inspect "${CONTAINER_NAME}" >/dev/null 2>&1
}

container_running() {
  [[ "$("${DOCKER[@]}" inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null || true)" == true ]]
}

check_host() {
  validate_settings
  detect_docker
  check_gpu
  info "Docker: $("${DOCKER[@]}" version --format '{{.Server.Version}}')"
  info "Wallet: ${WALLET}"
  info "Worker: ${WORKER}"
  info "Pool: ${POOL}"
  info "Image: ${IMAGE}"
  info "Pemeriksaan host selesai."
}

start_miner() {
  validate_settings
  detect_docker
  check_gpu

  if container_running; then
    info "Miner sudah berjalan: ${CONTAINER_NAME}"
    return 0
  fi

  if container_exists; then
    info "Menghapus container lama yang sudah berhenti..."
    "${DOCKER[@]}" container rm "${CONTAINER_NAME}" >/dev/null
  fi

  # Named volumes preserve the image's bundled model/cache when the container
  # is recreated. They are intentionally not deleted by the stop command.
  "${DOCKER[@]}" volume create "${MODEL_VOLUME}" >/dev/null
  "${DOCKER[@]}" volume create "${UPDATE_VOLUME}" >/dev/null

  info "Mengunduh/verifikasi image ${IMAGE} (unduhan pertama cukup besar)..."
  "${DOCKER[@]}" pull "${IMAGE}"

  info "Menjalankan miner di background..."
  "${DOCKER[@]}" run -d \
    --name "${CONTAINER_NAME}" \
    --restart unless-stopped \
    --stop-timeout 60 \
    --gpus "device=${GPU_INDEX}" \
    --shm-size "${SHM_SIZE}" \
    --ulimit memlock=-1 \
    --ulimit stack=67108864 \
    --mount "type=volume,source=${MODEL_VOLUME},target=/models" \
    --mount "type=volume,source=${UPDATE_VOLUME},target=/var/lib/lpminer-updates" \
    --env "WALLET=${WALLET}" \
    --env "LABEL=${WORKER}" \
    --env "POOL=${POOL}" \
    --env "GPU=0" \
    --env "FORCE_COLOR=1" \
    "${IMAGE}" >/dev/null

  sleep 3
  if ! container_running; then
    info "Container berhenti saat startup. Log terakhir:"
    "${DOCKER[@]}" logs --tail 100 "${CONTAINER_NAME}" || true
    return 1
  fi

  info "Miner aktif sebagai container ${CONTAINER_NAME}."
  info "Pantau dengan: ${CONTROL_COMMAND} logs"
  info "Hentikan dengan: ${CONTROL_COMMAND} stop"
}

show_logs() {
  detect_docker
  container_exists || die "Container ${CONTAINER_NAME} belum dibuat. Jalankan perintah start dahulu."
  info "Mengikuti log. Ctrl+C hanya menutup tampilan log; miner tetap berjalan."
  "${DOCKER[@]}" logs --tail 200 --follow "${CONTAINER_NAME}"
}

show_status() {
  detect_docker
  if ! container_exists; then
    info "Container ${CONTAINER_NAME} belum dibuat."
    return 1
  fi
  "${DOCKER[@]}" ps -a --filter "name=^/${CONTAINER_NAME}$" \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
  nvidia-smi --id="${GPU_INDEX}" \
    --query-gpu=name,memory.used,memory.total,utilization.gpu \
    --format=csv,noheader 2>/dev/null || true
}

stop_miner() {
  detect_docker
  if ! container_exists; then
    info "Container ${CONTAINER_NAME} tidak ada; tidak ada yang dihentikan."
    return 0
  fi
  if container_running; then
    info "Menghentikan ${CONTAINER_NAME}..."
    "${DOCKER[@]}" stop --time 60 "${CONTAINER_NAME}" >/dev/null
    info "Miner berhenti. Volume model/cache tetap disimpan."
  else
    info "Miner sudah berhenti."
  fi
}

command_name="${1:-run}"
case "${command_name}" in
  run)
    start_miner
    show_logs
    ;;
  start)
    start_miner
    ;;
  logs)
    show_logs
    ;;
  status)
    show_status
    ;;
  stop)
    stop_miner
    ;;
  restart)
    stop_miner
    start_miner
    ;;
  check)
    check_host
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage >&2
    die "Perintah tidak dikenal: ${command_name}"
    ;;
esac
