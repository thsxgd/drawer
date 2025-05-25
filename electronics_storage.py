#!/usr/bin/env python3
"""
Raspberry Pi Elektronikus Alkatrész Tároló
Komplett alkalmazás LED vezérléssel és webes felülettel

Használat:
    python3 electronics_storage.py

Automatikus függőség telepítés és kezelés.
"""

import os
import sys
import json
import time
import threading
import subprocess
from datetime import datetime
from pathlib import Path

def check_and_install_dependencies():
    """Függőségek ellenőrzése és telepítése"""
    required_packages = ['flask', 'RPi.GPIO']
    missing_packages = []
    
    for package in required_packages:
        try:
            __import__(package.replace('-', '_'))
        except ImportError:
            missing_packages.append(package)
    
    if missing_packages:
        print("📦 Hiányzó függőségek telepítése...")
        
        # Először próbáljuk apt-tal
        apt_packages = {
            'flask': 'python3-flask',
            'RPi.GPIO': 'python3-rpi.gpio'
        }
        
        try:
            for package in missing_packages:
                if package in apt_packages:
                    print(f"   Telepítés: {apt_packages[package]}")
                    result = subprocess.run([
                        'sudo', 'apt', 'install', '-y', apt_packages[package]
                    ], capture_output=True, text=True)
                    
                    if result.returncode == 0:
                        print(f"   ✅ {package} telepítve apt-tal")
                        continue
            
            # Ha apt nem működik, virtual environment
            missing_after_apt = []
            for package in required_packages:
                try:
                    __import__(package.replace('-', '_'))
                except ImportError:
                    missing_after_apt.append(package)
            
            if missing_after_apt:
                print("🐍 Virtual environment létrehozása...")
                venv_path = Path.home() / 'electronics_storage_venv'
                
                if not venv_path.exists():
                    subprocess.run([sys.executable, '-m', 'venv', str(venv_path)], check=True)
                
                pip_path = venv_path / 'bin' / 'pip'
                subprocess.run([str(pip_path), 'install', '--upgrade', 'pip'], check=True)
                
                for package in missing_after_apt:
                    print(f"   Telepítés venv-ben: {package}")
                    subprocess.run([str(pip_path), 'install', package], check=True)
                
                python_path = venv_path / 'bin' / 'python'
                print(f"✅ Virtual environment: {venv_path}")
                print("🔄 Újraindítás virtual environment-ben...")
                
                # Újraindítás a venv-ben
                os.execv(str(python_path), [str(python_path)] + sys.argv)
                
        except subprocess.CalledProcessError as e:
            print(f"❌ Telepítési hiba: {e}")
            print("\n🔧 Manuális telepítés:")
            print("sudo apt install python3-flask python3-rpi.gpio")
            print("vagy")
            print("pip3 install flask RPi.GPIO --break-system-packages")
            sys.exit(1)

# Függőségek ellenőrzése
check_and_install_dependencies()

# Import után
from flask import Flask, jsonify, request, send_file
import RPi.GPIO as GPIO

class ElectronicsStorage:
    def __init__(self):
        self.app = Flask(__name__)
        self.setup_gpio()
        self.setup_routes()
        self.data_file = Path.home() / "electronics_storage_data.json"
        self.led_states = {f"{row}-{col}": False for row in range(1, 9) for col in range(1, 5)}
        print("🔧 Elektronikus Alkatrész Tároló inicializálva")
        print(f"📊 {len([p for p in self.LED_PINS.values() if p is not None])} LED konfigurálva")
        
    def setup_gpio(self):
        """GPIO beállítások"""
        GPIO.setmode(GPIO.BCM)
        GPIO.setwarnings(False)
        
        # LED pin mapping (28 LED GPIO 2-29 pineken)
        self.LED_PINS = {}
        gpio_pins = [2, 3, 4, 14, 15, 18, 17, 27, 22, 23, 24, 10, 9, 25, 11, 8, 
                    7, 1, 12, 16, 20, 21, 19, 26, 13, 6, 5, 0]
        
        pin_index = 0
        for row in range(1, 8):  # 7 sor (28 LED)
            for col in range(1, 5):  # 4 oszlop
                drawer_id = f"{row}-{col}"
                if pin_index < len(gpio_pins):
                    self.LED_PINS[drawer_id] = gpio_pins[pin_index]
                    GPIO.setup(gpio_pins[pin_index], GPIO.OUT)
                    GPIO.output(gpio_pins[pin_index], GPIO.LOW)
                    pin_index += 1
        
        # 8. sor üres marad (nincs elég LED)
        for col in range(1, 5):
            self.LED_PINS[f"8-{col}"] = None
    
    def setup_routes(self):
        """Flask route-ok"""
        @self.app.route('/')
        def index():
            return '''<!DOCTYPE html>
<html lang="hu">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Elektronikus Alkatrész Tároló</title>
    <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@300;400;500;600;700&family=Space+Grotesk:wght@400;500;600;700&display=swap" rel="stylesheet">
    <style>
        :root {
            --black: #000000; --white: #ffffff; --gray: #888888; --light-gray: #cccccc;
            --green: #00ff00; --transition: all 0.15s ease;
            --font-mono: 'JetBrains Mono', monospace; --font-main: 'Space Grotesk', sans-serif;
        }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: var(--font-main); color: var(--white); background: var(--black); line-height: 1.5; }
        .container { max-width: 1400px; margin: 0 auto; padding: 0 20px; }
        .header { position: fixed; top: 0; left: 0; right: 0; z-index: 1000; background: rgba(0,0,0,0.95); backdrop-filter: blur(30px); border-bottom: 1px solid rgba(255,255,255,0.1); padding: 15px 0; }
        .header-content { display: flex; justify-content: space-between; align-items: center; }
        .logo { font-family: var(--font-mono); font-size: 1.25rem; font-weight: 700; letter-spacing: 0.1em; text-transform: uppercase; }
        .search-container { flex: 1; max-width: 600px; margin: 0 40px; position: relative; }
        .search-input { width: 100%; padding: 12px 50px 12px 20px; background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.2); border-radius: 2px; color: var(--white); font-family: var(--font-mono); font-size: 0.9rem; transition: var(--transition); }
        .search-input:focus { outline: none; border-color: var(--white); background: rgba(255,255,255,0.1); }
        .search-input::placeholder { color: var(--gray); }
        .search-button { position: absolute; right: 10px; top: 50%; transform: translateY(-50%); background: none; border: none; color: var(--white); cursor: pointer; padding: 5px; border-radius: 2px; transition: var(--transition); }
        .search-button:hover { background: rgba(255,255,255,0.1); }
        .status-indicator { display: flex; align-items: center; gap: 10px; font-family: var(--font-mono); font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.05em; }
        .status-dot { width: 8px; height: 8px; border-radius: 50%; background: var(--green); animation: pulse 2s infinite; }
        @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }
        .main-content { margin-top: 80px; padding: 40px 0; }
        .control-panel { background: rgba(255,255,255,0.03); border: 1px solid rgba(255,255,255,0.1); border-radius: 2px; padding: 30px; margin-bottom: 40px; }
        .control-panel h2 { font-family: var(--font-mono); font-size: 1rem; text-transform: uppercase; letter-spacing: 0.1em; margin-bottom: 20px; opacity: 0.8; }
        .control-buttons { display: flex; gap: 15px; flex-wrap: wrap; }
        .control-btn { padding: 10px 20px; background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.2); border-radius: 2px; color: var(--white); font-family: var(--font-mono); font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.05em; cursor: pointer; transition: var(--transition); }
        .control-btn:hover { background: rgba(255,255,255,0.1); border-color: var(--white); }
        .drawer-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; margin-bottom: 40px; }
        .drawer { background: rgba(255,255,255,0.03); border: 1px solid rgba(255,255,255,0.1); border-radius: 2px; padding: 20px; cursor: pointer; transition: var(--transition); min-height: 150px; }
        .drawer:hover { background: rgba(255,255,255,0.08); border-color: rgba(255,255,255,0.3); }
        .drawer.highlighted { border-color: var(--green); box-shadow: 0 0 20px rgba(0,255,0,0.3); }
        .drawer-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px; }
        .drawer-id { font-family: var(--font-mono); font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.05em; opacity: 0.6; }
        .led-indicator { width: 12px; height: 12px; border-radius: 50%; background: rgba(255,255,255,0.2); transition: var(--transition); cursor: pointer; }
        .led-indicator.on { background: var(--green); box-shadow: 0 0 10px var(--green); }
        .led-indicator.disabled { background: rgba(255,255,255,0.1); cursor: not-allowed; }
        .drawer-content { min-height: 80px; }
        .drawer-items { list-style: none; }
        .drawer-items li { padding: 3px 0; font-size: 0.85rem; color: var(--light-gray); border-bottom: 1px solid rgba(255,255,255,0.05); }
        .empty-drawer { color: var(--gray); font-style: italic; text-align: center; padding: 20px 0; }
        .search-results { background: rgba(255,255,255,0.03); border: 1px solid rgba(255,255,255,0.1); border-radius: 2px; padding: 30px; margin-bottom: 40px; display: none; }
        .search-results.show { display: block; }
        .result-item { display: flex; justify-content: space-between; align-items: center; padding: 15px 0; border-bottom: 1px solid rgba(255,255,255,0.05); cursor: pointer; transition: var(--transition); }
        .result-item:hover { background: rgba(255,255,255,0.05); }
        .result-info { flex: 1; }
        .result-name { font-weight: 600; margin-bottom: 5px; }
        .result-location { font-family: var(--font-mono); font-size: 0.8rem; color: var(--gray); }
        .result-count { font-family: var(--font-mono); font-size: 0.9rem; color: var(--white); }
        .modal { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.9); z-index: 2000; backdrop-filter: blur(20px); }
        .modal.show { display: flex; align-items: center; justify-content: center; }
        .modal-content { background: var(--black); border: 1px solid rgba(255,255,255,0.2); border-radius: 2px; padding: 40px; max-width: 600px; width: 90%; max-height: 80vh; overflow-y: auto; }
        .modal-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 30px; }
        .modal-title { font-family: var(--font-mono); font-size: 1.2rem; text-transform: uppercase; letter-spacing: 0.1em; }
        .close-btn { background: none; border: none; color: var(--white); font-size: 1.5rem; cursor: pointer; padding: 5px; border-radius: 2px; transition: var(--transition); }
        .close-btn:hover { background: rgba(255,255,255,0.1); }
        .form-group { margin-bottom: 20px; }
        .form-label { display: block; font-family: var(--font-mono); font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 8px; opacity: 0.8; }
        .form-input, .form-textarea { width: 100%; padding: 12px 15px; background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.2); border-radius: 2px; color: var(--white); font-family: var(--font-main); transition: var(--transition); }
        .form-input:focus, .form-textarea:focus { outline: none; border-color: var(--white); background: rgba(255,255,255,0.1); }
        .form-textarea { resize: vertical; min-height: 100px; }
        .save-btn { width: 100%; padding: 15px; background: var(--white); color: var(--black); border: none; border-radius: 2px; font-family: var(--font-mono); font-size: 0.9rem; text-transform: uppercase; letter-spacing: 0.05em; cursor: pointer; transition: var(--transition); }
        .save-btn:hover { background: var(--light-gray); }
        @media (max-width: 768px) { .drawer-grid { grid-template-columns: repeat(2, 1fr); gap: 15px; } .search-container { margin: 0 20px; } }
        @media (max-width: 480px) { .drawer-grid { grid-template-columns: 1fr; } .header-content { flex-direction: column; gap: 15px; } .search-container { margin: 0; max-width: none; } }
    </style>
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
                    <span>Online</span>
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
            <div class="drawer-grid" id="drawerGrid"></div>
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
                    <textarea class="form-textarea" id="drawerItems" placeholder="pl.&#10;LED piros 5mm (x20)&#10;LED kék 3mm (x15)"></textarea>
                </div>
                <div class="form-group">
                    <label class="form-label">Megjegyzések</label>
                    <textarea class="form-textarea" id="drawerNotes" placeholder="További információk..."></textarea>
                </div>
                <button type="submit" class="save-btn">Mentés</button>
            </form>
        </div>
    </div>
    <script>
        let drawers = {}, currentDrawer = null, ledStates = {}, allLEDsOn = false;
        const API_BASE = '/api';
        
        document.addEventListener('DOMContentLoaded', function() {
            initializeDrawers();
            generateDrawerGrid();
            loadDrawerData();
            document.getElementById('searchInput').addEventListener('input', debounce(performSearch, 300));
            document.getElementById('drawerForm').addEventListener('submit', saveDrawer);
            document.getElementById('drawerModal').addEventListener('click', function(e) {
                if (e.target === this) closeModal();
            });
        });
        
        function initializeDrawers() {
            for (let row = 1; row <= 8; row++) {
                for (let col = 1; col <= 4; col++) {
                    const id = `${row}-${col}`;
                    drawers[id] = { id, name: '', items: [], notes: '', row, col };
                    ledStates[id] = false;
                }
            }
        }
        
        function generateDrawerGrid() {
            const grid = document.getElementById('drawerGrid');
            grid.innerHTML = '';
            for (let row = 1; row <= 8; row++) {
                for (let col = 1; col <= 4; col++) {
                    const id = `${row}-${col}`;
                    const drawer = drawers[id];
                    const hasLED = row <= 7;
                    
                    const drawerElement = document.createElement('div');
                    drawerElement.className = 'drawer';
                    drawerElement.setAttribute('data-id', id);
                    drawerElement.onclick = () => openDrawerModal(id);
                    
                    drawerElement.innerHTML = `
                        <div class="drawer-header">
                            <div class="drawer-id">Fiók ${row}-${col}</div>
                            <div class="led-indicator ${hasLED ? '' : 'disabled'}" id="led-${id}" 
                                 onclick="${hasLED ? `toggleLED('${id}', event)` : ''}"></div>
                        </div>
                        <div class="drawer-content">
                            <div class="drawer-name" id="name-${id}">${drawer.name || 'Üres fiók'}</div>
                            <ul class="drawer-items" id="items-${id}">
                                ${drawer.items.length === 0 ? '<li class="empty-drawer">Nincs tartalom</li>' : 
                                  drawer.items.map(item => `<li>${item}</li>`).join('')}
                            </ul>
                        </div>
                    `;
                    grid.appendChild(drawerElement);
                }
            }
        }
        
        function openDrawerModal(drawerId) {
            currentDrawer = drawerId;
            const drawer = drawers[drawerId];
            document.getElementById('modalTitle').textContent = `Fiók ${drawer.row}-${drawer.col} Szerkesztése`;
            document.getElementById('drawerName').value = drawer.name;
            document.getElementById('drawerItems').value = drawer.items.join('\\n');
            document.getElementById('drawerNotes').value = drawer.notes;
            document.getElementById('drawerModal').classList.add('show');
        }
        
        function closeModal() {
            document.getElementById('drawerModal').classList.remove('show');
            currentDrawer = null;
        }
        
        function saveDrawer(e) {
            e.preventDefault();
            if (!currentDrawer) return;
            const name = document.getElementById('drawerName').value.trim();
            const itemsText = document.getElementById('drawerItems').value.trim();
            const notes = document.getElementById('drawerNotes').value.trim();
            const items = itemsText ? itemsText.split('\\n').filter(item => item.trim()) : [];
            drawers[currentDrawer] = { ...drawers[currentDrawer], name, items, notes };
            updateDrawerDisplay(currentDrawer);
            saveDrawerData();
            closeModal();
        }
        
        function updateDrawerDisplay(drawerId) {
            const drawer = drawers[drawerId];
            document.getElementById(`name-${drawerId}`).textContent = drawer.name || 'Üres fiók';
            document.getElementById(`items-${drawerId}`).innerHTML = drawer.items.length === 0 ? 
                '<li class="empty-drawer">Nincs tartalom</li>' : 
                drawer.items.map(item => `<li>${item}</li>`).join('');
        }
        
        function toggleLED(drawerId, event) {
            event.stopPropagation();
            fetch(`${API_BASE}/led/${drawerId}/toggle`, { method: 'POST' })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    ledStates[drawerId] = data.state;
                    updateLEDDisplay(drawerId);
                }
            }).catch(error => console.error('LED toggle error:', error));
        }
        
        function updateLEDDisplay(drawerId) {
            const ledElement = document.getElementById(`led-${drawerId}`);
            ledElement.classList.toggle('on', ledStates[drawerId]);
        }
        
        function toggleAllLEDs() {
            allLEDsOn = !allLEDsOn;
            fetch(`${API_BASE}/led/all/${allLEDsOn ? 'on' : 'off'}`, { method: 'POST' })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    Object.keys(ledStates).forEach(drawerId => {
                        const row = parseInt(drawerId.split('-')[0]);
                        if (row <= 7) {
                            ledStates[drawerId] = allLEDsOn;
                            updateLEDDisplay(drawerId);
                        }
                    });
                }
            }).catch(error => console.error('All LEDs error:', error));
        }
        
        function testMode() {
            fetch(`${API_BASE}/led/test`, { method: 'POST' })
            .then(response => response.json())
            .then(data => data.success && console.log('Test mode activated'))
            .catch(error => console.error('Test mode error:', error));
        }
        
        function clearHighlights() {
            document.querySelectorAll('.drawer.highlighted').forEach(drawer => drawer.classList.remove('highlighted'));
            document.getElementById('searchResults').classList.remove('show');
            document.getElementById('searchInput').value = '';
        }
        
        function performSearch() {
            const query = document.getElementById('searchInput').value.trim().toLowerCase();
            if (!query) return clearHighlights();
            
            const results = [], matchingDrawers = [];
            Object.values(drawers).forEach(drawer => {
                const matches = [];
                if (drawer.name.toLowerCase().includes(query)) matches.push({ type: 'name', text: drawer.name });
                drawer.items.forEach(item => {
                    if (item.toLowerCase().includes(query)) matches.push({ type: 'item', text: item });
                });
                if (drawer.notes.toLowerCase().includes(query)) matches.push({ type: 'notes', text: drawer.notes });
                
                if (matches.length > 0) {
                    results.push({ drawer, matches });
                    matchingDrawers.push(drawer.id);
                }
            });
            
            displaySearchResults(results);
            highlightDrawers(matchingDrawers);
        }
        
        function displaySearchResults(results) {
            const resultsContainer = document.getElementById('searchResultsList');
            const searchResults = document.getElementById('searchResults');
            
            if (results.length === 0) return searchResults.classList.remove('show');
            
            resultsContainer.innerHTML = results.map(result => `
                <div class="result-item" onclick="highlightDrawer('${result.drawer.id}')">
                    <div class="result-info">
                        <div class="result-name">${result.drawer.name || 'Névtelen fiók'}</div>
                        <div class="result-location">Fiók ${result.drawer.row}-${result.drawer.col}</div>
                    </div>
                    <div class="result-count">${result.matches.length} találat</div>
                </div>
            `).join('');
            
            searchResults.classList.add('show');
        }
        
        function highlightDrawers(drawerIds) {
            document.querySelectorAll('.drawer.highlighted').forEach(drawer => drawer.classList.remove('highlighted'));
            drawerIds.forEach(drawerId => {
                const drawerElement = document.querySelector(`[data-id="${drawerId}"]`);
                if (drawerElement) drawerElement.classList.add('highlighted');
                
                const row = parseInt(drawerId.split('-')[0]);
                if (row <= 7) {
                    fetch(`${API_BASE}/led/${drawerId}/toggle`, { method: 'POST' })
                    .then(response => response.json())
                    .then(data => {
                        if (data.success) {
                            ledStates[drawerId] = data.state;
                            updateLEDDisplay(drawerId);
                        }
                    });
                }
            });
        }
        
        function highlightDrawer(drawerId) {
            clearHighlights();
            highlightDrawers([drawerId]);
            const drawerElement = document.querySelector(`[data-id="${drawerId}"]`);
            if (drawerElement) drawerElement.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }
        
        function saveDrawerData() {
            fetch(`${API_BASE}/drawers`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(drawers)
            }).then(response => response.json())
            .then(data => data.success && console.log('Data saved'))
            .catch(error => console.error('Save error:', error));
        }
        
        function loadDrawerData() {
            fetch(`${API_BASE}/drawers`)
            .then(response => response.json())
            .then(data => {
                if (data.drawers) {
                    drawers = data.drawers;
                    Object.keys(drawers).forEach(drawerId => updateDrawerDisplay(drawerId));
                }
            }).catch(error => console.error('Load error:', error));
        }
        
        function exportData() {
            fetch(`${API_BASE}/export`)
            .then(response => response.blob())
            .then(blob => {
                const url = window.URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = `alkartesz_tarolo_${new Date().toISOString().split('T')[0]}.json`;
                document.body.appendChild(a);
                a.click();
                window.URL.revokeObjectURL(url);
                document.body.removeChild(a);
            }).catch(error => console.error('Export error:', error));
        }
        
        function debounce(func, wait) {
            let timeout;
            return function executedFunction(...args) {
                const later = () => { clearTimeout(timeout); func(...args); };
                clearTimeout(timeout);
                timeout = setTimeout(later, wait);
            };
        }
    </script>
</body>
</html>'''
        
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
                'success': True, 'status': 'online',
                'led_count': len([p for p in self.LED_PINS.values() if p is not None]),
                'led_states': self.led_states, 'timestamp': datetime.now().isoformat()
            })
    
    def set_led(self, drawer_id, state):
        if drawer_id in self.LED_PINS and self.LED_PINS[drawer_id] is not None:
            GPIO.output(self.LED_PINS[drawer_id], GPIO.HIGH if state else GPIO.LOW)
            self.led_states[drawer_id] = state
            return True
        return False
    
    def run_led_test(self):
        def test_sequence():
            try:
                # Összes LED ki
                for drawer_id in self.LED_PINS.keys():
                    if self.LED_PINS[drawer_id] is not None:
                        self.set_led(drawer_id, False)
                time.sleep(0.5)
                
                # Soronként végigmegy
                for row in range(1, 8):
                    for col in range(1, 5):
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
        try:
            if self.data_file.exists():
                with open(self.data_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
        except Exception as e:
            print(f"Adatok betöltési hiba: {e}")
        
        # Alapértelmezett adatok
        default_data = {}
        for row in range(1, 9):
            for col in range(1, 5):
                drawer_id = f"{row}-{col}"
                default_data[drawer_id] = {
                    'id': drawer_id, 'name': '', 'items': [], 'notes': '', 'row': row, 'col': col
                }
        return default_data
    
    def save_drawer_data(self, data):
        try:
            with open(self.data_file, 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            return True
        except Exception as e:
            print(f"Adatok mentési hiba: {e}")
            return False
    
    def run(self, host='0.0.0.0', port=5000, debug=False):
        try:
            print("🚀 Elektronikus Alkatrész Tároló indítása...")
            print(f"🌐 Elérhető: http://localhost:{port}")
            
            import socket
            try:
                hostname = socket.gethostname()
                local_ip = socket.gethostbyname(hostname)
                print(f"📱 Hálózati elérés: http://{local_ip}:{port}")
            except:
                print("📱 Hálózati IP nem elérhető")
            
            print("\n📋 GPIO pin kiosztás:")
            pin_count = 0
            for row in range(1, 8):
                row_pins = []
                for col in range(1, 5):
                    drawer_id = f"{row}-{col}"
                    if self.LED_PINS[drawer_id] is not None:
                        row_pins.append(f"Fiók {drawer_id}: GPIO {self.LED_PINS[drawer_id]}")
                        pin_count += 1
                if row_pins:
                    print(f"   {' | '.join(row_pins)}")
            print(f"   Összesen: {pin_count} LED")
            
            print("\n💡 Használat:")
            print("   - Nyisd meg a weboldalt böngészőben")
            print("   - Kattints egy fiókra a szerkesztéshez")
            print("   - Használd a keresőt alkatrészek megtalálásához")
            print("   - A LED-ek automatikusan jelzik a találatokat")
            print("   - Ctrl+C: Leállítás")
            
            print("\n🔌 Fizikai kapcsolások:")
            print("   - 28 LED pozitív lába -> 5V (VSYS/Pin 2 vagy 4)")
            print("   - 28 LED negatív lába -> GPIO pinekre egyenként")
            print("   - Ellenállás: 220-330Ω minden LED-hez ajánlott")
            
            self.app.run(host=host, port=port, debug=debug)
            
        except KeyboardInterrupt:
            print("\n⏹️  Alkalmazás leállítása...")
        except Exception as e:
            print(f"\n❌ Hiba: {e}")
        finally:
            try:
                GPIO.cleanup()
                print("✅ GPIO cleanup kész")
            except:
                pass

def main():
    import argparse
    parser = argparse.ArgumentParser(description='Elektronikus Alkatrész Tároló')
    parser.add_argument('--host', default='0.0.0.0', help='Host cím (default: 0.0.0.0)')
    parser.add_argument('--port', type=int, default=5000, help='Port szám (default: 5000)')
    parser.add_argument('--debug', action='store_true', help='Debug mód')
    
    args = parser.parse_args()
    
    print("🔧 Raspberry Pi Elektronikus Alkatrész Tároló")
    print("=" * 50)
    
    # Raspberry Pi ellenőrzése
    try:
        with open('/proc/device-tree/model', 'r') as f:
            model = f.read()
        if 'Raspberry Pi' not in model:
            print("⚠️  Figyelem: Nem Raspberry Pi-n futtatod!")
            print("GPIO funkciók nem fognak működni.")
    except FileNotFoundError:
        print("⚠️  Figyelem: Nem Raspberry Pi rendszert észleltem!")
        print("GPIO funkciók nem fognak működni.")
    
    # Alkalmazás indítása
    app = ElectronicsStorage()
    app.run(host=args.host, port=args.port, debug=args.debug)

if __name__ == '__main__':
    main()
