#!/bin/bash
set -e

# === 設定値 (必要に応じて変更) ===
ALIST_ADMIN_PASSWORD="Alist@2024!"  # Alist管理者パスワード
ALIST_PORT="5244"                  # Alistポート
GITHUB_REPO="uefn1/Ser"        # GitHubリポジトリ (例: myuser/myrepo)
RUNNER_NAME="my-runner"            # Runner名
UPLOAD_DIR="/srv/alist/uploads"    # アップロードディレクトリ
# ==================================

echo "🚀 GitHub Actions サーバー化セットアップを開始します..."

# 1. 依存パッケージをインストール
echo "📦 依存パッケージをインストール..."
sudo apt update -y
sudo apt install -y git curl wget docker.io docker-compose jq

# 2. Dockerを起動
echo "🐳 Dockerを起動..."
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER

# 3. Alist用のディレクトリを作成
echo "📁 ディレクトリを作成..."
sudo mkdir -p /srv/alist/{data,uploads}
sudo chown -R $USER:$USER /srv/alist

# 4. AlistをDocker Composeで起動
echo "🌐 Alistを起動..."
cat > docker-compose.yml << 'EOL'
version: '3.8'
services:
  alist:
    image: xhofe/alist:latest
    container_name: alist
    restart: unless-stopped
    ports:
      - "${ALIST_PORT}:5244"
    volumes:
      - /srv/alist/data:/opt/alist/data
      - /srv/alist/uploads:/srv/alist/uploads
    environment:
      - ALIST_ADMIN_PASSWORD=${ALIST_ADMIN_PASSWORD}
EOL

docker-compose up -d

# 5. Alistの起動を待機
echo "⏳ Alistの起動を待機..."
sleep 10

# 6. Alistの管理画面URLを表示
echo "✅ Alistが起動しました!"
echo "   管理画面: http://$(hostname -I | awk '{print $1}'):${ALIST_PORT}"
echo "   ユーザー名: admin"
echo "   パスワード: ${ALIST_ADMIN_PASSWORD}"

# 7. Self-Hosted Runnerをセットアップ
echo "🏃 Self-Hosted Runnerをセットアップ..."
mkdir -p ~/actions-runner
cd ~/actions-runner

# アーキテクチャを判定
ARCH=$(uname -m)
case $ARCH in
  x86_64) RUNNER_URL="https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz" ;;
  aarch64) RUNNER_URL="https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-arm64-2.311.0.tar.gz" ;;
  *) echo "❌ 対応していないアーキテクチャ: $ARCH"; exit 1 ;;
esac

curl -L -o actions-runner.tar.gz $RUNNER_URL
tar xzf actions-runner.tar.gz
rm actions-runner.tar.gz

# Runnerを登録 (手動でトークンを入力)
echo "🔑 GitHub Runner登録トークンを入力してください:"
echo "   (GitHub → Settings → Actions → Runners → New self-hosted runner から取得)"
read -p "   トークン: " RUNNER_TOKEN

./config.sh --url https://github.com/${GITHUB_REPO} --token ${RUNNER_TOKEN} --name ${RUNNER_NAME} --unattended

# Runnerを起動 (systemd)
sudo ./svc.sh install
sudo ./svc.sh start

echo "✅ Self-Hosted Runnerが起動しました!"
echo "   Runner名: ${RUNNER_NAME}"
echo "   リポジトリ: ${GITHUB_REPO}"

# 8. AlistのWebhook設定を表示
echo ""
echo "📌 AlistのWebhookを手動で設定してください:"
echo "   1. Alist管理画面 (http://$(hostname -I | awk '{print $1}'):${ALIST_PORT}) にアクセス"
echo "   2. Settings → Webhook → 新規追加"
echo "   3. 以下の設定を入力:"
echo ""
echo "      名前: github-release-trigger"
echo "      URL: https://api.github.com/repos/${GITHUB_REPO}/dispatches"
echo "      メソッド: POST"
echo "      ヘッダー:"
echo "        Accept: application/vnd.github.v3+json"
echo "        Authorization: token \${{ secrets.GITHUB_TOKEN }}"
echo "      ボディ:"
echo '        {"event_type": "file_uploaded", "client_payload": {"file_path": "{{.path}}", "file_name": "{{.name}}"}}'
echo "      イベント: File Uploaded ✅"
echo ""
echo "🎉 セットアップ完了!"
echo "   ファイルをAlistにアップロードすると、自動でReleaseが作成されます。"
echo "   古いReleaseは削除されません。"
