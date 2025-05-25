#!/bin/bash
#
# Raspberry Pi Elektronikus Alkatrész Tároló - Virtual Environment Setup
# 
# Ez a script automatikusan beállít mindent venv-ben és elindítja az alkalmazást
#
# Használat:
#   chmod +x setup_venv.sh
#   ./setup_venv.sh
#

set -e  # Kilépés hiba esetén

# Színek
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funkciók
print_status() {
    echo -e "${BLUE}🔄 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Banner
echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          ELEKTRONIKUS ALKATRÉSZ TÁROLÓ - VENV SETUP         ║"
echo "║                Virtual Environment Telepítő                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Változók
PROJECT_NAME="electronics_storage"
PROJECT_DIR="$HOME/$PROJECT_NAME"
VENV_DIR="$PROJECT_DIR/venv"
PYTHON_FILE="$PROJECT_DIR/electronics_storage.py"

# Ellenőrzések
print_status "Rendszer ellenőrzése..."

if [[ ! -f /proc/device-tree/model ]] || ! grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
    print_warning "Ez nem Raspberry Pi, de folytatom..."
fi

if [[ $EUID -eq 0 ]]; then
    print_error "Ne futtasd root-ként! Használd a normál felhasználót."
    exit 1
fi

print_success "Rendszer ellenőrzése kész"

# Python3 és venv ellenőrzése
print_status "Python3 és venv ellenőrzése..."

if ! command -v python3 &> /dev/null; then
    print_error "Python3 nincs telepítve!"
    echo "Telepítsd: sudo apt install python3"
    exit 1
fi

if ! python3 -m venv --help &> /dev/null; then
    print_status "Python3-venv telepítése..."
    sudo apt update
    sudo apt install -y python3-venv python3-pip
fi

print_success "Python3 és venv elérhető"

# Projekt könyvtár létrehozása
print_status "Projekt könyvtár létrehozása..."
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"
print_success "Projekt könyvtár: $PROJECT_DIR"

# Virtual environment létrehozása
if [ ! -d "$VENV_DIR" ]; then
    print_status "Virtual environment létrehozása..."
    python3 -m venv "$VENV_DIR"
    print_success "Virtual environment létrehozva"
else
    print_success "Virtual environment már létezik"
fi

# Virtual environment aktiválása
print_status "Virtual environment aktiválása..."
source "$VENV_DIR/bin/activate"
print_success "Virtual environment aktiválva"

# Pip frissítése
print_status "Pip frissítése..."
pip install --upgrade pip > /dev/null 2>&1
print_success "Pip frissítve"

# Függőségek telepítése
print_status "Függőségek telepítése..."
pip install flask RPi.GPIO > /dev/null 2>&1
print_success "Függőségek telepítve (flask, RPi.GPIO)"

# Python alkalmazás fájl létrehozása
print_status "Python alkalmazás létrehozása..."

cat > "$PYTHON_FILE" << 'EOF'
#!/usr/bin/env python3
"""
Raspberry Pi Elektronikus Alkatrész Tároló
Virtual Environment verzió

Használat:
    source venv/bin/activate
    python electronics_storage.py
"""

import os
import sys
import json
import time
import threading
from datetime import datetime
from pathlib import Path

# Flask és GPIO import
try:
    from flask import Flask, jsonify, request, send_file
    import RPi.GPIO as GPIO
except ImportError as e:
    print("❌ Hiányzó függőségek!")
    print(f"Import hiba: {e}")
    print("Ellenőrizd, hogy a virtual environment aktív és a csomagok telepítve vannak.")
    print("Telepítés: pip install flask RPi.GPIO")
    sys.exit(1)

class ElectronicsStorage:
    def __init__(self):
        self.app = Flask(__name__)
        self.setup_gpio()
        self.setup_routes()
        
        # Adatfájl a projekt könyvtárban
        self.data_file = Path(__file__).parent / "data" / "drawers.json"
        self.data_file.parent.mkdir(exist_ok=True)
        
        # LED állapotok
        self.led_states = {f"{row}-{col}": False for row in range(1, 9) for col in range(1, 5)}
        
        print("🔧 Elektronikus Alkatrész Tároló inicializálva (venv)")
        print(f"📊 {len([p for p in self.LED_PINS.values() if p is not None])} LED konfigurálva")
        print(f"📁 Adatok helye: {self.data_file}")
        
    def setup_gpio(self):
        """GPIO beállítások és LED pin mapping"""
        GPIO.setmode(GPIO.BCM)
        GPIO.setwarnings(False)
        
        # LED pin mapping (4×8 grid) - 28 LED GPIO 2-29 pineken
        self.LED_PINS = {}
        gpio_pins = [2, 3, 4, 14, 15, 18, 17, 27, 22, 23, 24, 10, 9, 25, 11, 8, 
                    7, 1, 12, 16, 20, 21, 19, 26, 13, 6, 5, 0]
        
        pin_index = 0
        for row in range(1, 8):  # 7 sor (28 LED)
            for col in range(1, 5):  # 4 oszlop
                drawer_id = f"{row}-{col}"
                if pin_index < len(gpio_pins):
                    self.LED_PINS[drawer_id] = gpio_pins[pin_index]
                    try:
                        GPIO.setup(gpio_pins[pin_index], GPIO.OUT)
                        GPIO.output(gpio_pins[pin_index], GPIO.LOW)
                    except Exception as e:
                        print(f"⚠️  GPIO {gpio_pins[pin_index]} hiba: {e}")
                    pin_index += 1
        
        # 8. sor üres marad (nincs elég LED)
        for col in range(1, 5):
            self.LED_PINS[f"8-{col}"] = None
    
    def setup_routes(self):
        """Flask route-ok beállítása"""
        
        @self.app.route('/')
        def index():
            return self.get_html()
        
        @self.app.route('/static/style.css')
        def get_css():
            return self.get_css_content(), 200, {'Content-Type': 'text/css'}
        
        @self.app.route('/static/script.js')
        def get_js():
            return self.get_js_content(), 200, {'Content-Type': 'application/javascript'}
        
        @self.app.route('/api/drawers', methods=['GET'])
        def get_drawers():
            data = self.load_drawer_data()
            return jsonify({'success': True, 'drawers': data})
        
        @self.app.route('/api/drawers', methods=['POST'])
        def save_drawers():
            try:
                data = request.get_json()
                if self.save_drawer_data(data):
                    return jsonify({'success': True})
                else:
                    return jsonify({'success': False, 'error': 'Mentési hiba'})
            except Exception as e:
                return jsonify({'success': False, 'error': str(e)})
        
        @self.app.route('/api/led/<drawer_id>/toggle', methods=['POST'])
        def toggle_led(drawer_id):
            try:
                current_state = self.led_states.get(drawer_id, False)
                new_state = not current_state
                
                if self.set_led(drawer_id, new_state):
                    return jsonify({'success': True, 'state': new_state})
                else:
                    return jsonify({'success': False, 'error': 'Érvénytelen fiók ID'})
            except Exception as e:
                return jsonify({'success': False, 'error': str(e)})
        
        @self.app.route('/api/led/all/<state>', methods=['POST'])
        def set_all_leds(state):
            try:
                led_state = state.lower() == 'on'
                
                for drawer_id in self.LED_PINS.keys():
                    if self.LED_PINS[drawer_id] is not None:
                        self.set_led(drawer_id, led_state)
                
                return jsonify({'success': True, 'state': led_state})
            except Exception as e:
                return jsonify({'success': False, 'error': str(e)})
        
        @self.app.route('/api/led/test', methods=['POST'])
        def test_leds():
            self.run_led_test()
            return jsonify({'success': True})
        
        @self.app.route('/api/export', methods=['GET'])
        def export_data():
            try:
                data = self.load_drawer_data()
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                filename = f"alkartesz_tarolo_{timestamp}.json"
                
                temp_file = f"/tmp/{filename}"
                with open(temp_file, 'w', encoding='utf-8') as f:
                    json.dump(data, f, ensure_ascii=False, indent=2)
                
                return send_file(temp_file, as_attachment=True, download_name=filename)
            except Exception as e:
                return jsonify({'success': False, 'error': str(e)})
        
        @self.app.route('/api/status', methods=['GET'])
        def get_status():
            return jsonify({
                'success': True,
                'status': 'online',
                'venv': os.environ.get('VIRTUAL_ENV', 'Not in venv'),
                'led_count': len([p for p in self.LED_PINS.values() if p is not None]),
                'led_states': self.led_states,
                'timestamp': datetime.now().isoformat()
            })
    
    def set_led(self, drawer_id, state):
        """LED állapot beállítása"""
        if drawer_id in self.LED_PINS and self.LED_PINS[drawer_id] is not None:
            try:
                GPIO.output(self.LED_PINS[drawer_id], GPIO.HIGH if state else GPIO.LOW)
                self.led_states[drawer_id] = state
                return True
            except Exception as e:
                print(f"LED {drawer_id} hiba: {e}")
                return False
        return False
    
    def run_led_test(self):
        """LED teszt futtatása külön szálban"""
        def test_sequence():
            try:
                print("🔄 LED teszt indítása...")
                
                # Összes LED ki
                for drawer_id in self.LED_PINS.keys():
                    if self.LED_PINS[drawer_id] is not None:
                        self.set_led(drawer_id, False)
                time.sleep(0.5)
                
                # Soronként végigmegy
                for row in range(1, 8):  # 7 sor
                    for col in range(1, 5):  # 4 oszlop
                        drawer_id = f"{row}-{col}"
                        if self.LED_PINS[drawer_id] is not None:
                            self.set_led(drawer_id, True)
                            time.sleep(0.15)
                            self.set_led(drawer_id, False)
                
                time.sleep(0.5)
                
                # Összes fel és le
                for drawer_id in self.LED_PINS.keys():
                    if self.LED_PINS[drawer_id] is not None:
                        self.set_led(drawer_id, True)
                time.sleep(1)
                
                for drawer_id in self.LED_PINS.keys():
                    if self.LED_PINS[drawer_id] is not None:
                        self.set_led(drawer_id, False)
                        
                print("✅ LED teszt befejezve")
            except Exception as e:
                print(f"❌ LED teszt hiba: {e}")
        
        test_thread = threading.Thread(target=test_sequence)
        test_thread.daemon = True
        test_thread.start()
    
    def load_drawer_data(self):
        """Fiók adatok betöltése"""
        try:
            if self.data_file.exists():
                with open(self.data_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
        except Exception as e:
            print(f"Adatok betöltési hiba: {e}")
        
        # Alapértelmezett adatok
        default_data = {}
        for row in range(1, 9):  # 8 sor
            for col in range(1, 5):  # 4 oszlop
                drawer_id = f"{row}-{col}"
                default_data[drawer_id] = {
                    'id': drawer_id,
                    'name': '',
                    'items': [],
                    'notes': '',
                    'row': row,
                    'col': col
                }
        return default_data
    
    def save_drawer_data(self, data):
        """Fiók adatok mentése"""
        try:
            with open(self.data_file, 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            return True
        except Exception as e:
            print(f"Adatok mentési hiba: {e}")
            return False
    
    def get_html(self):
        """HTML tartalom - ugyanaz mint az eredeti"""
        return '''<!DOCTYPE html>
<html lang="hu">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Elektronikus Alkatrész Tároló</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@300;400;500;600;700&family=Space+Grotesk:wght@400;500;600;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="/static/style.css">
</head>
<body>
    <header class="header">
        <div class="container">
            <div class="header-content">
                <div class="logo">Alkatrész Tároló</div>
                <div class="search-container">
                    <input type="text" class="search-input" placeholder="Keresés alkatrészek között..." id="searchInput">
                    <button class="search-button" onclick="performSearch()">🔍</button>
                </div>
                <div class="status-indicator">
                    <div class="status-dot"></div>
                    <span>Online (venv)</span>
                </div>
            </div>
        </div>
    </header>

    <main class="main-content">
        <div class="container">
            <div class="control-panel">
                <h2>LED Vezérlés</h2>
                <div class="control-buttons">
                    <button class="control-btn" onclick="toggleAllLEDs()">Összes LED Ki/Be</button>
                    <button class="control-btn" onclick="testMode()">Teszt Mód</button>
                    <button class="control-btn" onclick="clearHighlights()">Kiemelések Törlése</button>
                    <button class="control-btn" onclick="exportData()">Adatok Exportálása</button>
                </div>
            </div>

            <div class="search-results" id="searchResults">
                <h3>Keresési Eredmények</h3>
                <div id="searchResultsList"></div>
            </div>

            <div class="drawer-grid" id="drawerGrid">
                <!-- Drawers will be generated by JavaScript -->
            </div>
        </div>
    </main>

    <div class="modal" id="drawerModal">
        <div class="modal-content">
            <div class="modal-header">
                <h3 class="modal-title" id="modalTitle">Fiók Szerkesztése</h3>
                <button class="close-btn" onclick="closeModal()">&times;</button>
            </div>
            <form id="drawerForm">
                <div class="form-group">
                    <label class="form-label">Fiók Neve</label>
                    <input type="text" class="form-input" id="drawerName" placeholder="pl. LED-ek, Ellenállások...">
                </div>
                <div class="form-group">
                    <label class="form-label">Alkatrészek (soronként egy)</label>
                    <textarea class="form-textarea" id="drawerItems" placeholder="pl.&#10;LED piros 5mm (x20)&#10;LED kék 3mm (x15)&#10;LED RGB (x5)"></textarea>
                </div>
                <div class="form-group">
                    <label class="form-label">Megjegyzések</label>
                    <textarea class="form-textarea" id="drawerNotes" placeholder="További információk..."></textarea>
                </div>
                <button type="submit" class="save-btn">Mentés</button>
            </form>
        </div>
    </div>

    <script src="/static/script.js"></script>
</body>
</html>'''
    
    def get_css_content(self):
        """CSS tartalom - rövidített, kompakt verzió"""
        return ''':root {--black: #000000; --white: #ffffff; --gray: #888888; --light-gray: #cccccc; --green: #00ff00; --red: #ff0000; --radius: 2px; --transition: all 0.15s ease; --font-mono: 'JetBrains Mono', monospace; --font-main: 'Space Grotesk', sans-serif;}
* { margin: 0; padding: 0; box-sizing: border-box; }
body {font-family: var(--font-main); color: var(--white); background: var(--black); line-height: 1.5; overflow-x: hidden; -webkit-font-smoothing: antialiased;}
.container { max-width: 1400px; margin: 0 auto; padding: 0 20px; }
.header {position: fixed; top: 0; left: 0; right: 0; z-index: 1000; background: rgba(0, 0, 0, 0.95); backdrop-filter: blur(30px); border-bottom: 1px solid rgba(255, 255, 255, 0.1); padding: 15px 0;}
.header-content { display: flex; justify-content: space-between; align-items: center; }
.logo {font-family: var(--font-mono); font-size: 1.25rem; font-weight: 700; letter-spacing: 0.1em; text-transform: uppercase;}
.search-container { flex: 1; max-width: 600px; margin: 0 40px; position: relative; }
.search-input {width: 100%; padding: 12px 50px 12px 20px; background: rgba(255, 255, 255, 0.05); border: 1px solid rgba(255, 255, 255, 0.2); border-radius: var(--radius); color: var(--white); font-family: var(--font-mono); font-size: 0.9rem; transition: var(--transition);}
.search-input:focus {outline: none; border-color: var(--white); background: rgba(255, 255, 255, 0.1);}
.search-input::placeholder { color: var(--gray); }
.search-button {position: absolute; right: 10px; top: 50%; transform: translateY(-50%); background: none; border: none; color: var(--white); cursor: pointer; padding: 5px; border-radius: var(--radius); transition: var(--transition);}
.search-button:hover { background: rgba(255, 255, 255, 0.1); }
.status-indicator {display: flex; align-items: center; gap: 10px; font-family: var(--font-mono); font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.05em;}
.status-dot {width: 8px; height: 8px; border-radius: 50%; background: var(--green); animation: pulse 2s infinite;}
@keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }
.main-content { margin-top: 80px; padding: 40px 0; }
.control-panel {background: rgba(255, 255, 255, 0.03); border: 1px solid rgba(255, 255, 255, 0.1); border-radius: var(--radius); padding: 30px; margin-bottom: 40px;}
.control-panel h2 {font-family: var(--font-mono); font-size: 1rem; text-transform: uppercase; letter-spacing: 0.1em; margin-bottom: 20px; opacity: 0.8;}
.control-buttons { display: flex; gap: 15px; flex-wrap: wrap; }
.control-btn {padding: 10px 20px; background: rgba(255, 255, 255, 0.05); border: 1px solid rgba(255, 255, 255, 0.2); border-radius: var(--radius); color: var(--white); font-family: var(--font-mono); font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.05em; cursor: pointer; transition: var(--transition);}
.control-btn:hover {background: rgba(255, 255, 255, 0.1); border-color: var(--white);}
.control-btn.active { background: var(--white); color: var(--black); }
.drawer-grid {display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; margin-bottom: 40px;}
.drawer {background: rgba(255, 255, 255, 0.03); border: 1px solid rgba(255, 255, 255, 0.1); border-radius: var(--radius); padding: 20px; cursor: pointer; transition: var(--transition); position: relative; min-height: 150px;}
.drawer:hover {background: rgba(255, 255, 255, 0.08); border-color: rgba(255, 255, 255, 0.3);}
.drawer.highlighted {border-color: var(--green); box-shadow: 0 0 20px rgba(0, 255, 0, 0.3);}
.drawer-header {display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px;}
.drawer-id {font-family: var(--font-mono); font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.05em; opacity: 0.6;}
.led-indicator {width: 12px; height: 12px; border-radius: 50%; background: rgba(255, 255, 255, 0.2); transition: var(--transition); cursor: pointer;}
.led-indicator.on { background: var(--green); box-shadow: 0 0 10px var(--green); }
.led-indicator.disabled { background: rgba(255, 255, 255, 0.1); cursor: not-allowed; }
.drawer-content { min-height: 80px; }
.drawer-items { list-style: none; }
.drawer-items li {padding: 3px 0; font-size: 0.85rem; color: var(--light-gray); border-bottom: 1px solid rgba(255, 255, 255, 0.05);}
.drawer-items li:last-child { border-bottom: none; }
.empty-drawer {color: var(--gray); font-style: italic; text-align: center; padding: 20px 0;}
.search-results {background: rgba(255, 255, 255, 0.03); border: 1px solid rgba(255, 255, 255, 0.1); border-radius: var(--radius); padding: 30px; margin-bottom: 40px; display: none;}
.search-results.show { display: block; }
.search-results h3 {font-family: var(--font-mono); font-size: 1rem; text-transform: uppercase; letter-spacing: 0.1em; margin-bottom: 20px; opacity: 0.8;}
.result-item {display: flex; justify-content: space-between; align-items: center; padding: 15px 0; border-bottom: 1px solid rgba(255, 255, 255, 0.05); cursor: pointer; transition: var(--transition);}
.result-item:hover { background: rgba(255, 255, 255, 0.05); }
.result-item:last-child { border-bottom: none; }
.result-info { flex: 1; }
.result-name { font-weight: 600; margin-bottom: 5px; }
.result-location {font-family: var(--font-mono); font-size: 0.8rem; color: var(--gray);}
.result-count {font-family: var(--font-mono); font-size: 0.9rem; color: var(--white);}
.modal {display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0, 0, 0, 0.9); z-index: 2000; backdrop-filter: blur(20px);}
.modal.show { display: flex; align-items: center; justify-content: center; }
.modal-content {background: var(--black); border: 1px solid rgba(255, 255, 255, 0.2); border-radius: var(--radius); padding: 40px; max-width: 600px; width: 90%; max-height: 80vh; overflow-y: auto;}
.modal-header {display: flex; justify-content: space-between; align-items: center; margin-bottom: 30px;}
.modal-title {font-family: var(--font-mono); font-size: 1.2rem; text-transform: uppercase; letter-spacing: 0.1em;}
.close-btn {background: none; border: none; color: var(--white); font-size: 1.5rem; cursor: pointer; padding: 5px; border-radius: var(--radius); transition: var(--transition);}
.close-btn:hover { background: rgba(255, 255, 255, 0.1); }
.form-group { margin-bottom: 20px; }
.form-label {display: block; font-family: var(--font-mono); font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 8px; opacity: 0.8;}
.form-input, .form-textarea {width: 100%; padding: 12px 15px; background: rgba(255, 255, 255, 0.05); border: 1px solid rgba(255, 255, 255, 0.2); border-radius: var(--radius); color: var(--white); font-family: var(--font-main); transition: var(--transition);}
.form-input:focus, .form-textarea:focus {outline: none; border-color: var(--white); background: rgba(255, 255, 255, 0.1);}
.form-textarea { resize: vertical; min-height: 100px; }
.save-btn {width: 100%; padding: 15px; background: var(--white); color: var(--black); border: none; border-radius: var(--radius); font-family: var(--font-mono); font-size: 0.9rem; text-transform: uppercase; letter-spacing: 0.05em; cursor: pointer; transition: var(--transition);}
.save-btn:hover { background: var(--light-gray); }
@media (max-width: 768px) {.drawer-grid { grid-template-columns: repeat(2, 1fr); gap: 15px; } .search-container { margin: 0 20px; } .control-buttons { justify-content: center; }}
@media (max-width: 480px) {.drawer-grid { grid-template-columns: 1fr; } .header-content { flex-direction: column; gap: 15px; } .search-container { margin: 0; max-width: none; }}'''
    
    def get_js_content(self):
        """JavaScript tartalom - teljes funkcionális verzió"""
        return '''let drawers={},currentDrawer=null,ledStates={},allLEDsOn=false;
const API_BASE='/api';

document.addEventListener('DOMContentLoaded',function(){
    initializeDrawers();generateDrawerGrid();loadDrawerData();
    document.getElementById('searchInput').addEventListener('input',debounce(performSearch,300));
    document.getElementById('drawerForm').addEventListener('submit',saveDrawer);
    document.getElementById('drawerModal').addEventListener('click',function(e){
        if(e.target===this)closeModal();
    });
});

function initializeDrawers(){
    for(let row=1;row<=8;row++){
        for(let col=1;col<=4;col++){
            const id=`${row}-${col}`;
            drawers[id]={id,name:'',items:[],notes:'',row,col};
            ledStates[id]=false;
        }
    }
}

function generateDrawerGrid(){
    const grid=document.getElementById('drawerGrid');
    grid.innerHTML='';
    for(let row=1;row<=8;row++){
        for(let col=1;col<=4;col++){
            const id=`${row}-${col}`;
            const drawer=drawers[id];
            const hasLED=row<=7;
            const drawerElement=document.createElement('div');
            drawerElement.className='drawer';
            drawerElement.setAttribute('data-id',id);
            drawerElement.onclick=()=>openDrawerModal(id);
            drawerElement.innerHTML=`
                <div class="drawer-header">
                    <div class="drawer-id">Fiók ${row}-${col}</div>
                    <div class="led-indicator ${hasLED?'':'disabled'}" id="led-${id}" 
                         onclick="${hasLED?`toggleLED('${id}',event)`:''}"></div>
                </div>
                <div class="drawer-content">
                    <div class="drawer-name" id="name-${id}">${drawer.name||'Üres fiók'}</div>
                    <ul class="drawer-items" id="items-${id}">
                        ${drawer.items.length===0?'<li class="empty-drawer">Nincs tartalom</li>':
                          drawer.items.map(item=>`<li>${item}</li>`).join('')}
                    </ul>
                </div>
            `;
            grid.appendChild(drawerElement);
        }
    }
}

function openDrawerModal(drawerId){
    currentDrawer=drawerId;
    const drawer=drawers[drawerId];
    document.getElementById('modalTitle').textContent=`Fiók ${drawer.row}-${drawer.col} Szerkesztése`;
    document.getElementById('drawerName').value=drawer.name;
    document.getElementById('drawerItems').value=drawer.items.join('\\n');
    document.getElementById('drawerNotes').value=drawer.notes;
    document.getElementById('drawerModal').classList.add('show');
}

function closeModal(){
    document.getElementById('drawerModal').classList.remove('show');
    currentDrawer=null;
}

function saveDrawer(e){
    e.preventDefault();
    if(!currentDrawer)return;
    const name=document.getElementById('drawerName').value.trim();
    const itemsText=document.getElementById('drawerItems').value.trim();
    const notes=document.getElementById('drawerNotes').value.trim();
    const items=itemsText?itemsText.split('\\n').filter(item=>item.trim()):[];
    drawers[currentDrawer]={...drawers[currentDrawer],name,items,notes};
    updateDrawerDisplay(currentDrawer);
    saveDrawerData();
    closeModal();
}

function updateDrawerDisplay(drawerId){
    const drawer=drawers[drawerId];
    document.getElementById(`name-${drawerId}`).textContent=drawer.name||'Üres fiók';
    document.getElementById(`items-${drawerId}`).innerHTML=drawer.items.length===0?
        '<li class="empty-drawer">Nincs tartalom</li>':
        drawer.items.map(item=>`<li>${item}</li>`).join('');
}

function toggleLED(drawerId,event){
    event.stopPropagation();
    fetch(`${API_BASE}/led/${drawerId}/toggle`,{method:'POST'})
    .then(response=>response.json())
    .then(data=>{
        if(data.success){
            ledStates[drawerId]=data.state;
            updateLEDDisplay(drawerId);
        }
    }).catch(error=>console.error('LED toggle error:',error));
}

function updateLEDDisplay(drawerId){
    const ledElement=document.getElementById(`led-${drawerId}`);
    ledElement.classList.toggle('on',ledStates[drawerId]);
}

function toggleAllLEDs(){
    allLEDsOn=!allLEDsOn;
    fetch(`${API_BASE}/led/all/${allLEDsOn?'on':'off'}`,{method:'POST'})
    .then(response=>response.json())
    .then(data=>{
        if(data.success){
            Object.keys(ledStates).forEach(drawerId=>{
                const row=parseInt(drawerId.split('-')[0]);
                if(row<=7){
                    ledStates[drawerId]=allLEDsOn;
                    updateLEDDisplay(drawerId);
                }
            });
        }
    }).catch(error=>console.error('All LEDs toggle error:',error));
}

function testMode(){
    fetch(`${API_BASE}/led/test`,{method:'POST'})
    .then(response=>response.json())
    .then(data=>data.success&&console.log('Test mode activated'))
    .catch(error=>console.error('Test mode error:',error));
}

function clearHighlights(){
    document.querySelectorAll('.drawer.highlighted').forEach(drawer=>drawer.classList.remove('highlighted'));
    document.getElementById('searchResults').classList.remove('show');
    document.getElementById('searchInput').value='';
}

function performSearch(){
    const query=document.getElementById('searchInput').value.trim().toLowerCase();
    if(!query)return clearHighlights();
    const results=[],matchingDrawers=[];
    Object.values(drawers).forEach(drawer=>{
        const matches=[];
        if(drawer.name.toLowerCase().includes(query))matches.push({type:'name',text:drawer.name});
        drawer.items.forEach(item=>{
            if(item.toLowerCase().includes(query))matches.push({type:'item',text:item});
        });
        if(drawer.notes.toLowerCase().includes(query))matches.push({type:'notes',text:drawer.notes});
        if(matches.length>0){
            results.push({drawer,matches});
            matchingDrawers.push(drawer.id);
        }
    });
    displaySearchResults(results);
    highlightDrawers(matchingDrawers);
}

function displaySearchResults(results){
    const resultsContainer=document.getElementById('searchResultsList');
    const searchResults=document.getElementById('searchResults');
    if(results.length===0)return searchResults.classList.remove('show');
    resultsContainer.innerHTML=results.map(result=>`
        <div class="result-item" onclick="highlightDrawer('${result.drawer.id}')">
            <div class="result-info">
                <div class="result-name">${result.drawer.name||'Névtelen fiók'}</div>
                <div class="result-location">Fiók ${result.drawer.row}-${result.drawer.col}</div>
            </div>
            <div class="result-count">${result.matches.length} találat</div>
        </div>
    `).join('');
    searchResults.classList.add('show');
}

function highlightDrawers(drawerIds){
    document.querySelectorAll('.drawer.highlighted').forEach(drawer=>drawer.classList.remove('highlighted'));
    drawerIds.forEach(drawerId=>{
        const drawerElement=document.querySelector(`[data-id="${drawerId}"]`);
        if(drawerElement)drawerElement.classList.add('highlighted');
        const row=parseInt(drawerId.split('-')[0]);
        if(row<=7){
            fetch(`${API_BASE}/led/${drawerId}/toggle`,{method:'POST'})
            .then(response=>response.json())
            .then(data=>{
                if(data.success){
                    ledStates[drawerId]=data.state;
                    updateLEDDisplay(drawerId);
                }
            });
        }
    });
}

function highlightDrawer(drawerId){
    clearHighlights();
    highlightDrawers([drawerId]);
    const drawerElement=document.querySelector(`[data-id="${drawerId}"]`);
    if(drawerElement)drawerElement.scrollIntoView({behavior:'smooth',block:'center'});
}

function saveDrawerData(){
    fetch(`${API_BASE}/drawers`,{
        method:'POST',
        headers:{'Content-Type':'application/json'},
        body:JSON.stringify(drawers)
    }).then(response=>response.json())
    .then(data=>data.success&&console.log('Data saved'))
    .catch(error=>console.error('Save error:',error));
}

function loadDrawerData(){
    fetch(`${API_BASE}/drawers`)
    .then(response=>response.json())
    .then(data=>{
        if(data.drawers){
            drawers=data.drawers;
            Object.keys(drawers).forEach(drawerId=>updateDrawerDisplay(drawerId));
        }
    }).catch(error=>console.error('Load error:',error));
}

function exportData(){
    fetch(`${API_BASE}/export`)
    .then(response=>response.blob())
    .then(blob=>{
        const url=window.URL.createObjectURL(blob);
        const a=document.createElement('a');
        a.href=url;
        a.download=`alkartesz_tarolo_${new Date().toISOString().split('T')[0]}.json`;
        document.body.appendChild(a);
        a.click();
        window.URL.revokeObjectURL(url);
        document.body.removeChild(a);
    }).catch(error=>console.error('Export error:',error));
}

function debounce(func,wait){
    let timeout;
    return function executedFunction(...args){
        const later=()=>{clearTimeout(timeout);func(...args);};
        clearTimeout(timeout);
        timeout=setTimeout(later,wait);
    };
}'''
    
    def run(self, host='0.0.0.0', port=5000, debug=False):
        """Alkalmazás indítása virtual environment-ben"""
        try:
            venv_path = os.environ.get('VIRTUAL_ENV', 'Nincs venv')
            print("🚀 Elektronikus Alkatrész Tároló indítása (Virtual Environment)")
            print(f"🐍 Virtual Environment: {venv_path}")
            print(f"🌐 Elérhető: http://localhost:{port}")
            
            # Helyi IP cím megjelenítése
            import socket
            try:
                hostname = socket.gethostname()
                local_ip = socket.gethostbyname(hostname)
                print(f"📱 Hálózati elérés: http://{local_ip}:{port}")
            except:
                print("📱 Hálózati IP nem elérhető")
            
            print(f"\n📁 Adatok mentési helye: {self.data_file}")
            print("\n📋 GPIO kiosztás (28 LED):")
            pin_count = 0
            for row in range(1, 8):
                row_pins = []
                for col in range(1, 5):
                    drawer_id = f"{row}-{col}"
                    if self.LED_PINS[drawer_id] is not None:
                        row_pins.append(f"Fiók {row}-{col}:GPIO{self.LED_PINS[drawer_id]}")
                        pin_count += 1
                if row_pins:
                    print(f"   {' | '.join(row_pins)}")
            print(f"   Összesen: {pin_count} LED konfigurálva")
            
            print("\n💡 Használat:")
            print("   - Nyisd meg a weboldalt böngészőben")
            print("   - LED-ek a 8. sorban nincsenek (csak 28 LED)")
            print("   - Keresés automatikusan kigyújtja a megfelelő LED-eket")
            print("   - Fiók szerkesztése: kattints a fiókra")
            
            print("\n⚙️  Vezérlés:")
            print("   - Ctrl+C: Leállítás és GPIO cleanup")
            print("   - LED teszt: Összes LED tesztelése sorban")
            print("   - Virtual environment aktív")
            
            self.app.run(host=host, port=port, debug=debug)
            
        except KeyboardInterrupt:
            print("\n⏹️  Alkalmazás leállítása...")
        except Exception as e:
            print(f"\n❌ Hiba: {e}")
            print("Ellenőrizd a virtual environment aktiválását!")
        finally:
            self.cleanup()
    
    def cleanup(self):
        """GPIO és erőforrások tisztítása"""
        try:
            GPIO.cleanup()
            print("✅ GPIO cleanup kész")
        except Exception as e:
            print(f"⚠️  GPIO cleanup hiba: {e}")

def main():
    """Fő futtatási pont - Virtual Environment ellenőrzéssel"""
    print("🔧 Raspberry Pi Elektronikus Alkatrész Tároló (Virtual Environment)")
    print("=" * 70)
    
    # Virtual Environment ellenőrzése
    venv_path = os.environ.get('VIRTUAL_ENV')
    if not venv_path:
        print("⚠️  FIGYELEM: Nem virtual environment-ben futtatod!")
        print("Ajánlott használat:")
        print("  source venv/bin/activate")
        print("  python electronics_storage.py")
        print()
        response = input("Folytatod virtual environment nélkül? (y/n): ")
        if response.lower() != 'y':
            sys.exit(1)
    else:
        print(f"✅ Virtual Environment aktív: {venv_path}")
    
    # Argumentumok feldolgozása
    import argparse
    parser = argparse.ArgumentParser(description='Elektronikus Alkatrész Tároló (venv)')
    parser.add_argument('--host', default='0.0.0.0', help='Host cím (default: 0.0.0.0)')
    parser.add_argument('--port', type=int, default=5000, help='Port szám (default: 5000)')
    parser.add_argument('--debug', action='store_true', help='Debug mód')
    
    args = parser.parse_args()
    
    # Raspberry Pi ellenőrzése
    try:
        with open('/proc/device-tree/model', 'r') as f:
            model = f.read()
        if 'Raspberry Pi' not in model:
            print("⚠️  Figyelem: Nem Raspberry Pi-n futtatod!")
            print("LED funkciók nem fognak működni más rendszereken.")
            response = input("Folytatod? (y/n): ")
            if response.lower() != 'y':
                sys.exit(1)
        else:
            print(f"✅ Raspberry Pi észlelve: {model.strip()}")
    except FileNotFoundError:
        print("⚠️  Figyelem: Nem Raspberry Pi rendszert észleltem!")
        print("LED funkciók nem fognak működni.")
        response = input("Folytatod? (y/n): ")
        if response.lower() != 'y':
            sys.exit(1)
    
    # Alkalmazás indítása
    app = ElectronicsStorage()
    app.run(host=args.host, port=args.port, debug=args.debug)

if __name__ == '__main__':
    main()
EOF

chmod +x "$PYTHON_FILE"
print_success "Python alkalmazás létrehozva és futtathatóvá téve"

# requirements.txt létrehozása
print_status "Requirements.txt létrehozása..."
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
Flask==2.3.3
RPi.GPIO==0.7.1
EOF
print_success "Requirements.txt létrehozva"

# Futtatási scriptek létrehozása
print_status "Futtatási scriptek létrehozása..."

# Start script
cat > "$PROJECT_DIR/start.sh" << EOF
#!/bin/bash
# Elektronikus Alkatrész Tároló indító script (venv)

cd "$PROJECT_DIR"

# Virtual environment aktiválása
if [ -d "venv" ]; then
    source venv/bin/activate
    echo "✅ Virtual environment aktiválva"
else
    echo "❌ Virtual environment nem található!"
    echo "Futtasd újra a setup scriptet."
    exit 1
fi

# Alkalmazás indítása
echo "🚀 Alkalmazás indítása..."
python electronics_storage.py

# Deaktiválás (ha kilép)
deactivate
EOF

chmod +x "$PROJECT_DIR/start.sh"

# Stop script
cat > "$PROJECT_DIR/stop.sh" << 'EOF'
#!/bin/bash
# Elektronikus Alkatrész Tároló leállító script

echo "⏹️  Alkalmazás leállítása..."
pkill -f "electronics_storage.py"
echo "✅ Alkalmazás leállítva"
EOF

chmod +x "$PROJECT_DIR/stop.sh"

# Status script
cat > "$PROJECT_DIR/status.sh" << 'EOF'
#!/bin/bash
# Elektronikus Alkatrész Tároló státusz ellenőrző

echo "📊 Alkalmazás státusz:"
if pgrep -f "electronics_storage.py" > /dev/null; then
    echo "✅ Fut"
    echo "🌐 PID: $(pgrep -f 'electronics_storage.py')"
else
    echo "❌ Nem fut"
fi

echo ""
echo "🐍 Virtual Environment:"
if [ -d "$HOME/electronics_storage/venv" ]; then
    echo "✅ Létezik"
else
    echo "❌ Nem létezik"
fi

echo ""
echo "📁 Fájlok:"
ls -la "$HOME/electronics_storage/" 2>/dev/null || echo "❌ Projekt könyvtár nem található"
EOF

chmod +x "$PROJECT_DIR/status.sh"

print_success "Futtatási scriptek létrehozva"

# Adatok könyvtár létrehozása
mkdir -p "$PROJECT_DIR/data"
print_success "Adatok könyvtár létrehozva"

# GPIO jogosultságok ellenőrzése
print_status "GPIO jogosultságok ellenőrzése..."
if groups $USER | grep -q gpio; then
    print_success "GPIO jogosultságok rendben"
else
    print_status "GPIO csoport hozzáadása..."
    sudo usermod -a -G gpio $USER
    print_warning "GPIO jogosultságok beállítva - ÚJRAINDÍTÁS SZÜKSÉGES!"
fi

# Virtual environment tesztelése
print_status "Virtual environment tesztelése..."
if pip list | grep -q Flask; then
    print_success "Flask telepítve a venv-ben"
else
    print_error "Flask nem található a venv-ben"
    exit 1
fi

if pip list | grep -q RPi.GPIO; then
    print_success "RPi.GPIO telepítve a venv-ben"
else
    print_error "RPi.GPIO nem található a venv-ben"
    exit 1
fi

# Záró információk
echo
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                🎉 VIRTUAL ENVIRONMENT TELEPÍTÉS KÉSZ! 🎉    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${BLUE}📁 Projekt könyvtár:${NC} $PROJECT_DIR"
echo -e "${BLUE}🐍 Virtual Environment:${NC} $VENV_DIR"
echo -e "${BLUE}📄 Python fájl:${NC} $PYTHON_FILE"
echo
echo -e "${YELLOW}🚀 INDÍTÁS:${NC}"
echo "   cd $PROJECT_DIR"
echo "   ./start.sh"
echo
echo -e "${YELLOW}📱 VAGY MANUÁLISAN:${NC}"
echo "   cd $PROJECT_DIR"
echo "   source venv/bin/activate"
echo "   python electronics_storage.py"
echo
echo -e "${YELLOW}⚙️  KEZELÉS:${NC}"
echo "   ./start.sh     - Indítás"
echo "   ./stop.sh      - Leállítás"
echo "   ./status.sh    - Státusz"
echo
echo -e "${YELLOW}🔌 LED KAPCSOLÁSOK:${NC}"
echo "   - 28 LED pozitív láb -> 5V (VSYS)"
echo "   - 28 LED negatív láb -> GPIO 2-29"
echo "   - Layout: 4×7 grid (8. sor üres)"
echo
echo -e "${YELLOW}📂 FÁJLOK:${NC}"
echo "   - requirements.txt: Python függőségek"
echo "   - data/: Adattárolás"
echo "   - venv/: Virtual environment"
echo
echo -e "${GREEN}🎯 HASZNÁLAT:${NC}"
echo "1. cd $PROJECT_DIR && ./start.sh"
echo "2. Böngészőben: http://$(hostname -I | awk '{print $1}'):5000"
echo "3. Fiókokra kattintva szerkesztés"
echo "4. Keresés -> automatikus LED kiemelés"
echo
if ! groups $USER | grep -q gpio; then
    echo -e "${RED}⚠️  FONTOS: GPIO jogosultságokhoz újraindítás szükséges!${NC}"
    echo "sudo reboot"
fi

# Deaktiválás
deactivate
print_success "Virtual environment telepítés befejezve!"
