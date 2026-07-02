#!/bin/bash
# meTools / miEnter / miCutPaste / miRightClick — tam temizlik betiği
#
# Eski kopyaların Finder sağ tık menüsünde bıraktığı çift kayıtları temizler:
#   1. Çalışan uygulama ve eklenti süreçlerini kapatır
#   2. pluginkit'teki Finder Sync eklenti kayıtlarını siler
#   3. Diskteki tüm uygulama kopyalarını bulur, LaunchServices kaydını kaldırır
#   4. build/ ve DerivedData kopyalarını siler (kaynak kodlara dokunmaz)
#   5. Tercih dosyalarını ve Group Container'ı siler
#   6. Accessibility (TCC) izinlerini sıfırlar
#   7. Finder'ı yeniden başlatır
#
# Not: miViewer'a dokunmaz. /Applications içindeki kopyayı da kaldırmak için:
#   scripts/uninstall.sh --apps
set -uo pipefail

APPS=(meTools miEnter miCutPaste miRightClick)
BUNDLE_IDS=(com.metinaksu.metools com.metinaksu.mienter com.metinaksu.micutpaste com.metinaksu.miRightClick)
PROJECT_ROOT="$HOME/Project/My/MacOS"
GROUP_CONTAINER="$HOME/Library/Group Containers/Y5K2497B6G.com.metinaksu.metools"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

REMOVE_INSTALLED=false
[[ "${1:-}" == "--apps" ]] && REMOVE_INSTALLED=true

echo "==> 1/7 Çalışan süreçler kapatılıyor"
for app in "${APPS[@]}"; do
    pkill -if "${app}.app" 2>/dev/null && echo "    kapatıldı: $app"
done
sleep 1

echo "==> 2/7 Finder Sync eklenti kayıtları siliniyor (pluginkit)"
# miViewer hariç tüm com.metinaksu eklenti yollarını pluginkit'ten topla.
pluginkit -mAvvv -p com.apple.FinderSync 2>/dev/null \
    | awk -F' = ' '/Path = /{print $2}' \
    | grep -i "metinaksu\|meTools\|miEnter\|miCutPaste\|miRightClick" \
    | grep -vi miViewer \
    | while IFS= read -r appex; do
        echo "    kayıt siliniyor: $appex"
        pluginkit -r "$appex" 2>/dev/null
    done

echo "==> 3/7 Diskteki kopyalar bulunup LaunchServices kaydı kaldırılıyor"
FOUND_APPS=$(mdfind "kMDItemContentType == 'com.apple.application-bundle'" 2>/dev/null \
    | grep -iE "/(meTools|miEnter|miCutPaste|miRightClick)\.app$" || true)
if [[ -n "$FOUND_APPS" ]]; then
    while IFS= read -r app; do
        echo "    lsregister -u: $app"
        "$LSREG" -u "$app" >/dev/null 2>&1
    done <<< "$FOUND_APPS"
fi

echo "==> 4/7 Derleme kopyaları siliniyor (kaynak kodlara dokunulmuyor)"
for app in "${APPS[@]}"; do
    if [[ -d "$PROJECT_ROOT/$app/build" ]]; then
        echo "    siliniyor: $PROJECT_ROOT/$app/build"
        rm -rf "$PROJECT_ROOT/$app/build"
    fi
done
for dd in "$HOME/Library/Developer/Xcode/DerivedData"/{meTools,miEnter,miCutPaste,miRightClick}-*; do
    [[ -d "$dd" ]] || continue
    echo "    siliniyor: $dd"
    rm -rf "$dd"
done
if $REMOVE_INSTALLED; then
    for app in "${APPS[@]}"; do
        if [[ -d "/Applications/$app.app" ]]; then
            echo "    siliniyor: /Applications/$app.app"
            rm -rf "/Applications/$app.app"
        fi
    done
fi

echo "==> 5/7 Tercihler ve Group Container siliniyor"
for id in "${BUNDLE_IDS[@]}"; do
    rm -f "$HOME/Library/Preferences/$id.plist"
done
rm -rf "$GROUP_CONTAINER"
# Containers klasörü SIP korumalı olabilir; hata verirse zararsızdır.
for id in "${BUNDLE_IDS[@]}"; do
    rm -rf "$HOME/Library/Containers/$id" "$HOME/Library/Containers/$id.FinderExtension" 2>/dev/null
done

echo "==> 6/7 Accessibility (TCC) izinleri sıfırlanıyor"
for id in "${BUNDLE_IDS[@]}"; do
    tccutil reset Accessibility "$id" 2>/dev/null && echo "    sıfırlandı: $id"
done

echo "==> 7/7 Finder ve ayar önbellekleri yenileniyor"
killall cfprefsd 2>/dev/null
killall Finder 2>/dev/null
killall "System Settings" 2>/dev/null

echo
echo "==> Kalan üçüncü parti Finder Sync eklentileri:"
pluginkit -m -p com.apple.FinderSync | grep -vi apple || echo "    (yok)"
echo
echo "Bitti. Login Items'ta etkisiz bir 'meTools' girdisi kalabilir;"
echo "yeni kurulumda aynı bundle ID ile üzerine yazıldığı için kendiliğinden düzelir."
