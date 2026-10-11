#!/bin/bash

# ============================================================
# mac-tools — MacBook Air maintenance & setup toolkit
# Modules: cleanup · quarterly · organize · setup
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

LOG_FILE="$HOME/mac_tools_$(date +%Y%m%d_%H%M%S).log"

log()     { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $1" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"; }
info()    { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }
section() { echo -e "\n${BOLD}${GREEN}========== $1 ==========${NC}"; }

confirm() {
    read -p "$1 (y/n): " -n 1 -r; echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

disk_usage()    { df -h / | awk 'NR==2 {print $3 " used, " $4 " available"}'; }
available_gb()  { df -g / | awk 'NR==2 {print $4}'; }

# ============================================================
# MODULE 1 — CLEANUP (one-time deep clean)
# ============================================================
run_cleanup() {
    section "Mac Cleanup — Goal: Free 20 GB+"
    log "Initial disk usage: $(disk_usage)"
    INITIAL=$(available_gb)

    # External drive
    echo ""
    log "Available volumes:"; ls -1 /Volumes/ | tee -a "$LOG_FILE"; echo ""
    read -p "External drive name for backups (Enter to skip): " EXT_DRIVE
    if [[ -n "$EXT_DRIVE" && -d "/Volumes/$EXT_DRIVE" ]]; then
        BACKUP_DIR="/Volumes/$EXT_DRIVE/Mac_Cleanup_Backup_$(date +%Y%m%d)"
        mkdir -p "$BACKUP_DIR"
        log "Backup dir: $BACKUP_DIR"
    else
        warn "No external drive — backups skipped."
        BACKUP_DIR=""
    fi

    # --- Mail Import Archive ---
    section "Mail Import Archive"
    IMPORT_MBOX=$(find ~/Library/Mail/V10 -name "Import.mbox" -type d 2>/dev/null | head -1)
    if [[ -n "$IMPORT_MBOX" ]]; then
        SZ=$(du -sh "$IMPORT_MBOX" | awk '{print $1}')
        log "Found Import.mbox: $SZ"
        if confirm "Backup and remove Mail Import archive ($SZ)?"; then
            [[ -n "$BACKUP_DIR" ]] && { mkdir -p "$BACKUP_DIR/Mail_Backup"; cp -R "$IMPORT_MBOX" "$BACKUP_DIR/Mail_Backup/"; }
            rm -rf "$IMPORT_MBOX"; log "Removed Import.mbox — freed $SZ"
        fi
    else
        log "No Import.mbox found"
    fi

    # --- User Caches ---
    section "User Caches"
    SZ=$(du -sh ~/Library/Caches 2>/dev/null | awk '{print $1}')
    log "Cache size: $SZ"
    if confirm "Clear user caches ($SZ)?"; then
        rm -rf ~/Library/Caches/*; log "Caches cleared — freed $SZ"
    fi

    # --- Xcode / Developer data ---
    section "Xcode / Developer Data"
    if [[ -d ~/Library/Developer ]]; then
        SZ=$(du -sh ~/Library/Developer 2>/dev/null | awk '{print $1}')
        log "Developer data: $SZ"
        if confirm "Clean Xcode/Developer data ($SZ)?"; then
            [[ -d ~/Library/Developer/Xcode/DerivedData ]]        && rm -rf ~/Library/Developer/Xcode/DerivedData/*
            [[ -d ~/Library/Developer/Xcode/iOS\ DeviceSupport ]] && rm -rf ~/Library/Developer/Xcode/iOS\ DeviceSupport/*
            if [[ -d ~/Library/Developer/Xcode/Archives ]]; then
                confirm "  Remove Xcode Archives?" && rm -rf ~/Library/Developer/Xcode/Archives/*
            fi
            [[ -d ~/Library/Developer/CoreSimulator/Devices ]] && rm -rf ~/Library/Developer/CoreSimulator/Devices/*
            log "Developer data cleaned — freed ~$SZ"
        fi
    else
        log "No Developer directory found"
    fi

    # --- Mail DB optimization ---
    section "Mail Database Optimization"
    if confirm "Optimize Mail database?"; then
        killall Mail 2>/dev/null || true; sleep 2
        [[ -f ~/Library/Mail/V10/MailData/Envelope\ Index ]] && \
            sqlite3 ~/Library/Mail/V10/MailData/Envelope\ Index "VACUUM;" 2>/dev/null || warn "DB vacuum failed (may be locked)"
        if [[ -d ~/Library/Mail/V10/MailData/Downloads ]]; then
            SZ=$(du -sh ~/Library/Mail/V10/MailData/Downloads 2>/dev/null | awk '{print $1}')
            if confirm "  Also clear Mail downloads cache ($SZ)?"; then
                rm -rf ~/Library/Mail/V10/MailData/Downloads/*
                log "Mail download cache cleared ($SZ)"
            fi
        fi
    fi

    # --- Mail attachments ---
    section "Mail Attachments"
    ATTACH_COUNT=$(find ~/Library/Mail -type f \( -name "*.MOV" -o -name "*.MP4" -o -name "*.pdf" -o -name "*.mov" -o -name "*.mp4" \) -size +5M 2>/dev/null | wc -l | xargs)
    log "Large attachments (>5 MB): $ATTACH_COUNT"
    if [[ $ATTACH_COUNT -gt 0 && -n "$BACKUP_DIR" ]]; then
        if confirm "Move large attachments to external drive?"; then
            mkdir -p "$BACKUP_DIR/Mail_Attachments"
            find ~/Library/Mail -type f \( -name "*.MOV" -o -name "*.MP4" -o -name "*.pdf" -o -name "*.mov" -o -name "*.mp4" \) \
                -size +5M 2>/dev/null -exec mv {} "$BACKUP_DIR/Mail_Attachments/" \; 2>/dev/null || true
            log "Attachments moved"
        fi
    elif [[ $ATTACH_COUNT -gt 0 ]]; then
        warn "No external drive — attachment move skipped"
    fi

    # --- Font caches ---
    section "Font Caches"
    if confirm "Clear font caches? (needs sudo)"; then
        sudo atsutil databases -remove 2>/dev/null || warn "Font cache clear failed"
        log "Font caches cleared"
    fi

    # --- DNS ---
    section "DNS Cache"
    if confirm "Flush DNS cache? (needs sudo)"; then
        sudo dscacheutil -flushcache 2>/dev/null || true
        sudo killall -HUP mDNSResponder 2>/dev/null || true
        log "DNS flushed"
    fi

    # --- Time Machine snapshots ---
    section "Time Machine Local Snapshots"
    SNAP_COUNT=$(tmutil listlocalsnapshots / 2>/dev/null | wc -l | xargs)
    if [[ $SNAP_COUNT -gt 0 ]]; then
        log "Found $SNAP_COUNT snapshots"
        if confirm "Remove local Time Machine snapshots?"; then
            for snap in $(tmutil listlocalsnapshots / | awk -F'.' '{print $4}'); do
                sudo tmutil deletelocalsnapshots "$snap" 2>/dev/null || true
            done
            log "Snapshots removed"
        fi
    else
        log "No snapshots found"
    fi

    # --- Summary ---
    section "Cleanup Complete"
    log "Final disk usage: $(disk_usage)"
    FREED=$(( $(available_gb) - INITIAL ))
    if [[ $FREED -ge 20 ]]; then
        echo -e "${GREEN}SUCCESS — freed ${FREED} GB (goal: 20 GB)${NC}"
    else
        echo -e "${YELLOW}Freed ${FREED} GB (goal: 20 GB)${NC}"
        echo "  Tip: Check ~/Downloads, enable iCloud Optimize Mac Storage"
    fi
    log "Log: $LOG_FILE"
}

# ============================================================
# MODULE 2 — QUARTERLY MAINTENANCE
# ============================================================
run_quarterly() {
    section "Quarterly Mac Maintenance — $(date +"%B %Y")"
    log "Initial: $(disk_usage)"
    INITIAL=$(available_gb)

    # npm cache
    section "npm Cache"
    if command -v npm &>/dev/null; then
        SZ=$(du -sh ~/.npm 2>/dev/null | awk '{print $1}')
        log "npm cache: $SZ"
        confirm "Clear npm cache?" && npm cache clean --force && log "npm cache cleared"
    else
        info "npm not installed"
    fi

    # User caches
    section "User Caches"
    SZ=$(du -sh ~/Library/Caches 2>/dev/null | awk '{print $1}')
    log "Cache size: $SZ"
    confirm "Clear user caches?" && rm -rf ~/Library/Caches/* && log "Caches cleared"

    # Old node_modules
    section "Old node_modules (90+ days)"
    SEARCH_DIRS=()
    [[ -d ~/work ]]     && SEARCH_DIRS+=("~/work")
    [[ -d ~/personal ]] && SEARCH_DIRS+=("~/personal")
    [[ -d ~/archive ]]  && SEARCH_DIRS+=("~/archive")
    if [[ ${#SEARCH_DIRS[@]} -gt 0 ]]; then
        OLD_NM=$(find "${SEARCH_DIRS[@]/#\~/$HOME}" -name "node_modules" -type d -mtime +90 -prune 2>/dev/null || true)
        if [[ -n "$OLD_NM" ]]; then
            echo "$OLD_NM" | while read -r nm; do
                warn "Old node_modules: $(dirname "$nm") ($(du -sh "$nm" | awk '{print $1}'))"
            done
            if confirm "Remove old node_modules?"; then
                echo "$OLD_NM" | while read -r nm; do rm -rf "$nm"; log "Removed $nm"; done
            fi
        else
            info "No old node_modules found"
        fi
    else
        warn "No ~/work ~/personal ~/archive — run Organize first"
    fi

    # VS Code cache
    section "VS Code Cache"
    VSCODE_CACHE="$HOME/Library/Application Support/Code/CachedData"
    if [[ -d "$VSCODE_CACHE" ]]; then
        SZ=$(du -sh "$VSCODE_CACHE" 2>/dev/null | awk '{print $1}')
        log "VS Code cache: $SZ"
        if confirm "Clear VS Code cache?"; then
            rm -rf "${VSCODE_CACHE:?}/"* && log "VS Code cache cleared"
        fi
    else
        info "VS Code cache not found"
    fi

    # Trash
    section "Trash"
    if [[ -n "$(ls -A ~/.Trash 2>/dev/null)" ]]; then
        SZ=$(du -sh ~/.Trash 2>/dev/null | awk '{print $1}')
        log "Trash: $SZ"
        confirm "Empty trash?" && rm -rf ~/.Trash/* && log "Trash emptied"
    else
        info "Trash already empty"
    fi

    # Downloads
    section "Downloads Folder"
    if [[ -n "$(ls -A ~/Downloads 2>/dev/null)" ]]; then
        SZ=$(du -sh ~/Downloads 2>/dev/null | awk '{print $1}')
        FC=$(find ~/Downloads -type f | wc -l | xargs)
        log "Downloads: $SZ ($FC files)"
        info "Files older than 90 days:"
        find ~/Downloads -type f -mtime +90 2>/dev/null | head -10 | while read -r f; do echo "  $(basename "$f")"; done
        warn "Review ~/Downloads manually"
    else
        info "Downloads is clean"
    fi

    # Git status check
    section "Git Status Check"
    check_git() {
        local dir=$1
        [[ -d "$dir/.git" ]] || return
        local status; status=$(git -C "$dir" status --porcelain 2>/dev/null)
        [[ -n "$status" ]] && warn "$(basename "$dir") has uncommitted changes" || info "$(basename "$dir") is clean"
    }
    [[ -d ~/work ]]     && for d in ~/work/*/;     do check_git "$d"; done
    [[ -d ~/personal ]] && for d in ~/personal/*/; do check_git "$d"; done

    # External backup
    section "External Drive Backup"
    info "Volumes:"; ls -1 /Volumes/ | sed 's/^/  /'
    read -p "External drive name (Enter to skip): " EXT_DRIVE
    if [[ -n "$EXT_DRIVE" && -d "/Volumes/$EXT_DRIVE" ]]; then
        BACKUP_DIR="/Volumes/$EXT_DRIVE/Backups/$(date +%Y%m%d)"
        mkdir -p "$BACKUP_DIR"
        confirm "Backup ~/work?"     && [[ -d ~/work ]]     && rsync -av --exclude 'node_modules' ~/work/     "$BACKUP_DIR/work/"
        confirm "Backup ~/personal?" && [[ -d ~/personal ]] && rsync -av --exclude 'node_modules' ~/personal/ "$BACKUP_DIR/personal/"
        log "Backup complete: $BACKUP_DIR"
    else
        warn "No external drive — backup skipped"
    fi

    section "Quarterly Complete"
    log "Final: $(disk_usage)"
    FREED=$(( $(available_gb) - INITIAL ))
    log "Freed this session: ${FREED} GB"
    info "Next run: $(date -v+3m +"%B %Y")"
    log "Log: $LOG_FILE"
}

# ============================================================
# MODULE 3 — ORGANIZE PROJECTS
# ============================================================
run_organize() {
    section "Project Organizer"
    log "Scanning home directory for projects..."
    mkdir -p ~/work ~/personal ~/archive

    PROJECTS=()
    for dir in ~/*/; do
        dirname=$(basename "$dir")
        [[ "$dirname" =~ ^(Library|Applications|Desktop|Documents|Downloads|Movies|Music|Pictures|Public|Sites|work|personal|archive)$ ]] && continue
        [[ -d "$dir/.git" || -f "$dir/package.json" || -f "$dir/Cargo.toml" || -f "$dir/go.mod" || -f "$dir/pom.xml" ]] && PROJECTS+=("$dirname")
    done

    if [[ ${#PROJECTS[@]} -eq 0 ]]; then
        info "No unorganized projects found"; return
    fi

    info "Found ${#PROJECTS[@]} project(s):"
    for p in "${PROJECTS[@]}"; do
        SZ=$(du -sh ~/"$p" 2>/dev/null | awk '{print $1}')
        echo "  - $p ($SZ)"
    done

    echo ""
    echo "  [W] Work  [P] Personal  [A] Archive  [S] Skip"

    for proj in "${PROJECTS[@]}"; do
        PROJECT_PATH=~/"$proj"
        SZ=$(du -sh "$PROJECT_PATH" 2>/dev/null | awk '{print $1}')
        echo ""; info "Project: $proj ($SZ)"

        if [[ -d "$PROJECT_PATH/.git" ]]; then
            REMOTE=$(git -C "$PROJECT_PATH" remote -v 2>/dev/null | head -1)
            [[ -n "$REMOTE" ]] && echo "  Git: $REMOTE"
        fi

        NM_COUNT=$(find "$PROJECT_PATH" -name "node_modules" -type d 2>/dev/null | wc -l | xargs)
        [[ $NM_COUNT -gt 0 ]] && warn "Has $NM_COUNT node_modules folder(s)"

        read -p "Categorize '$proj' as [W]ork / [P]ersonal / [A]rchive / [S]kip: " -n 1 -r CAT; echo ""

        move_project() {
            local dest=$1
            if [[ $NM_COUNT -gt 0 ]] && confirm "  Clean node_modules before moving?"; then
                find "$PROJECT_PATH" -name "node_modules" -type d -prune -exec rm -rf {} \; 2>/dev/null || true
            fi
            mv "$PROJECT_PATH" "$dest/"
            log "Moved $proj to $dest/"
        }

        case $CAT in
            [Ww]) [[ ! -d ~/work/"$proj" ]]     && move_project ~/work     && ln -sf ~/work/"$proj"     ~/"$proj"-link 2>/dev/null ;;
            [Pp]) [[ ! -d ~/personal/"$proj" ]]  && move_project ~/personal && ln -sf ~/personal/"$proj" ~/"$proj"-link 2>/dev/null ;;
            [Aa]) [[ ! -d ~/archive/"$proj" ]]   && move_project ~/archive ;;
            [Ss]) log "Skipped $proj" ;;
            *)    warn "Invalid — skipping $proj" ;;
        esac
    done

    # Root node_modules check
    if [[ -d ~/node_modules ]]; then
        SZ=$(du -sh ~/node_modules | awk '{print $1}')
        warn "Found ~/node_modules ($SZ) — shouldn't be in home root"
        confirm "Remove ~/node_modules?" && rm -rf ~/node_modules && log "Removed ~/node_modules"
    fi

    confirm "Create Desktop shortcuts for work/personal?" && {
        [[ -d ~/work ]]     && ln -sf ~/work     ~/Desktop/Work
        [[ -d ~/personal ]] && ln -sf ~/personal ~/Desktop/Personal
        log "Desktop shortcuts created"
    }

    section "Organization Complete"
    [[ -n "$(ls -A ~/work 2>/dev/null)" ]]     && { info "~/work/";     ls ~/work     | sed 's/^/  /'; }
    [[ -n "$(ls -A ~/personal 2>/dev/null)" ]] && { info "~/personal/"; ls ~/personal | sed 's/^/  /'; }
    [[ -n "$(ls -A ~/archive 2>/dev/null)" ]]  && { info "~/archive/";  ls ~/archive  | sed 's/^/  /'; }
    log "Log: $LOG_FILE"
}

# ============================================================
# MODULE 4 — ENVIRONMENT SETUP (Mac Air)
# ============================================================
run_setup() {
    section "MacBook Air Environment Setup"
    warn "This installs Homebrew packages, Node, Ruby, Python packages, and configures shell."
    confirm "Continue with full setup?" || { info "Setup cancelled"; return; }

    # Homebrew
    section "Homebrew"
    if ! command -v brew &>/dev/null; then
        info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        info "Homebrew already installed — updating..."
        brew update
    fi

    # Formulae
    section "Homebrew Formulae"
    FORMULAE=(
        abseil aom aribb24 autoconf automake awscli-local bison brotli c-ares
        ca-certificates cairo certifi cffi chruby cjson cryptography dav1d expat
        ffmpeg flac fontconfig freetype frei0r fribidi gcc gettext gh ghostscript
        giflib git-lfs glib gmp gnutls go graphite2 harfbuzz highway hwloc
        icu4c@76 icu4c@77 imagemagick imath isl jasper jbig2dec jetty jpeg-turbo
        jpeg-xl lame leptonica libarchive libass libb2 libbluray libde265
        libdeflate libevent libffi libheif libidn libidn2 liblqr libmicrohttpd
        libmpc libnghttp2 libogg libomp libpng libraw librist libsamplerate
        libsndfile libsodium libsoxr libssh libtasn1 libtiff libtool libunibreak
        libunistring libuv libvidstab libvmaf libvorbis libvpx libx11 libxau
        libxcb libxdmcp libxext libxrender libyaml little-cms2 localstack lz4 lzo
        m4 maven mbedtls mkcert mongosh mpdecimal mpfr mpg123 mysql ncurses neonctl
        nettle node numpy onnx openblas opencore-amr openexr openjdk openjdk@17
        openjpeg openssl@3 openvino opus p11-kit pango pcre2 pixman protobuf
        protobuf@29 pugixml pycparser python-packaging python@3.12 python@3.13
        rav1e readline redis rubberband ruby-install sdl2 shared-mime-info snappy
        speex sqlite srt svt-av1 swiftlint tbb tesseract theora tmux unbound
        utf8proc vapor webp x264 x265 xorgproto xvid xz zeromq zimg zlib zstd
    )
    for pkg in "${FORMULAE[@]}"; do
        brew list --formula "$pkg" &>/dev/null \
            && info "  [already installed] $pkg" \
            || { info "  Installing $pkg..."; brew install "$pkg" || warn "  Failed: $pkg"; }
    done

    # Casks
    section "Homebrew Casks"
    CASKS=(chatgpt chromedriver dbeaver-community docker docker-desktop
           gstreamer-runtime mysqlworkbench sublime-text visual-studio-code wine-stable)
    for cask in "${CASKS[@]}"; do
        brew list --cask "$cask" &>/dev/null \
            && info "  [already installed] $cask" \
            || { info "  Installing $cask..."; brew install --cask "$cask" || warn "  Failed: $cask"; }
    done

    # git-lfs
    section "Git LFS"
    git lfs install && info "git-lfs initialized"

    # NVM + Node
    section "NVM + Node.js"
    export NVM_DIR="$HOME/.nvm"
    [[ ! -d "$NVM_DIR" ]] && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    for ver in 17.9.1 20.18.3 20.19.0; do
        nvm ls "$ver" &>/dev/null && info "  [installed] Node $ver" || nvm install "$ver"
    done
    nvm alias default 20.19.0; info "Default Node: 20.19.0"

    # Ruby
    section "Ruby 3.4.1"
    ruby-install --no-reinstall ruby 3.4.1 || warn "ruby-install: may already be installed"

    # Python packages
    section "Python Packages (pip3)"
    pip3 install --upgrade \
        awscli awscli-local boto3 botocore certifi cffi colorama cryptography \
        docutils jmespath localstack-client numpy openvino openvino-telemetry \
        packaging pyasn1 pycparser python-dateutil PyYAML rsa s3transfer six urllib3 \
        || warn "Some pip packages may have failed"

    # Shell config
    section "Shell Config (~/.zshrc)"
    ZSHRC="$HOME/.zshrc"; touch "$ZSHRC"
    add_line() {
        grep -qF "$2" "$ZSHRC" && info "  [present] $2" || { echo "$1" >> "$ZSHRC"; info "  Added: $2"; }
    }
    add_line 'export JAVA_HOME=$(/usr/libexec/java_home -v17)'                            'JAVA_HOME'
    add_line 'export PATH=$JAVA_HOME/bin:$PATH'                                            'JAVA_HOME/bin'
    add_line 'source /opt/homebrew/opt/chruby/share/chruby/chruby.sh'                     'chruby.sh'
    add_line 'source /opt/homebrew/opt/chruby/share/chruby/auto.sh'                       'auto.sh'
    add_line 'chruby ruby-3.4.1'                                                           'chruby ruby-3.4.1'
    add_line 'export NVM_DIR="$HOME/.nvm"'                                                 'NVM_DIR'
    add_line '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'                           'nvm.sh'
    add_line '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'         'nvm bash_completion'

    # Git config
    section "Git Config"
    git config --global user.name  "Peter Victoratos"
    git config --global user.email "pvictoratos@rocketmail.com"
    git config --global core.excludesfile "$HOME/.gitignore_global"
    git config --global filter.lfs.process "git-lfs filter-process"
    git config --global filter.lfs.required true
    git config --global filter.lfs.clean "git-lfs clean -- %f"
    git config --global filter.lfs.smudge "git-lfs smudge -- %f"
    info "gitconfig written"

    # Global gitignore
    section "Global Gitignore"
    if [[ -f "$HOME/.gitignore_global" ]]; then
        cp "$HOME/.gitignore_global" "$HOME/.gitignore_global.bak"
        info "Backed up existing ~/.gitignore_global to ~/.gitignore_global.bak"
    fi
    cat > "$HOME/.gitignore_global" <<'EOF'
*~
.DS_Store
.claude/
*.code-workspace
node_modules/
/test-results/
/playwright-report/
/blob-report/
/playwright/.cache/
EOF
    info "~/.gitignore_global written"

    # Directory structure
    section "Directory Structure"
    mkdir -p "$HOME/Desktop/work/work-local" "$HOME/Desktop/apps" "$HOME/Desktop/Personal" "$HOME/Documents/govt"
    info "Core folders created"

    # AWS config
    section "AWS Config"
    mkdir -p "$HOME/.aws"
    if [[ ! -f "$HOME/.aws/config" ]]; then
        printf '[default]\nregion = us-east-1\n' > "$HOME/.aws/config"
        info "~/.aws/config written (region: us-east-1)"
    else
        info "~/.aws/config already exists — not overwritten"
    fi

    section "Setup Complete"
    warn "Manual steps still required:"
    echo "  1. Copy ~/.aws/credentials from Mac Mini (AirDrop or secure channel)"
    echo "  2. Copy ~/.git-credentials from Mac Mini"
    echo "  3. Sync Xcode projects via git remote or AirDrop"
    echo "  4. Sync Obsidian Vault via iCloud"
    echo "  5. App Store / vendor installs:"
    echo "       Xcode, Slack, Spotify, Zoom, CleanShot X, Claude, FL Studio,"
    echo "       GarageBand, Harvest, Endel, Wireshark, SF Symbols, TestFlight"
    echo "  6. Windsurf: https://codeium.com/windsurf"
    echo '       Add to ~/.zshrc: export PATH="/Users/panagiotis/.codeium/windsurf/bin:$PATH"'
    echo ""
    echo "  Run: source ~/.zshrc"
    log "Log: $LOG_FILE"
}

# ============================================================
# MAIN MENU
# ============================================================
main_menu() {
    clear
    echo ""
    echo -e "${BOLD}============================================${NC}"
    echo -e "${BOLD}   mac-tools — MacBook Air Toolkit${NC}"
    echo -e "${BOLD}============================================${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Cleanup        — deep clean, free space"
    echo -e "  ${GREEN}2)${NC} Quarterly      — routine maintenance"
    echo -e "  ${GREEN}3)${NC} Organize       — sort projects into work/personal/archive"
    echo -e "  ${GREEN}4)${NC} Setup          — install dev environment from scratch"
    echo -e "  ${GREEN}q)${NC} Quit"
    echo ""
    read -p "Choose: " -n 1 -r CHOICE; echo ""

    case $CHOICE in
        1) run_cleanup ;;
        2) run_quarterly ;;
        3) run_organize ;;
        4) run_setup ;;
        [Qq]) echo "Bye."; exit 0 ;;
        *) warn "Invalid choice"; main_menu ;;
    esac
}

# Allow running a module directly: ./mac_tools.sh cleanup
case "${1:-}" in
    cleanup)   run_cleanup ;;
    quarterly) run_quarterly ;;
    organize)  run_organize ;;
    setup)     run_setup ;;
    *)         main_menu ;;
esac
