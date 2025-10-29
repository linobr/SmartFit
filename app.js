// SmartFit - Fashion Assistant Application

// State Management
const state = {
    currentPage: 'dashboard',
    wardrobe: [],
    outfits: [],
    savedOutfits: [],
    settings: {
        styles: ['casual'],
        location: 'New York',
        sustainabilityMode: true,
        affiliateMode: false
    },
    isPremium: false,
    currentFilter: {
        category: 'all',
        occasion: 'all',
        weather: 'all'
    }
};

// Mock Weather Data
const weatherConditions = [
    { temp: '22°C', condition: '☀️ Sunny', type: 'sunny' },
    { temp: '18°C', condition: '☁️ Cloudy', type: 'cloudy' },
    { temp: '15°C', condition: '🌧️ Rainy', type: 'rainy' },
    { temp: '8°C', condition: '❄️ Cold', type: 'cold' }
];

// Mock clothing categories for AI detection
const clothingCategories = ['tops', 'bottoms', 'shoes', 'accessories'];

// Initialize App
document.addEventListener('DOMContentLoaded', () => {
    initializeNavigation();
    initializeWardrobeUpload();
    initializeFilters();
    initializeSettings();
    initializePremiumModal();
    loadFromLocalStorage();
    updateDashboard();
    setRandomWeather();
});

// Navigation
function initializeNavigation() {
    const navLinks = document.querySelectorAll('.nav-link');
    navLinks.forEach(link => {
        link.addEventListener('click', (e) => {
            e.preventDefault();
            const page = link.getAttribute('data-page');
            navigateToPage(page);
        });
    });

    // Quick action buttons
    document.querySelectorAll('[data-navigate]').forEach(btn => {
        btn.addEventListener('click', () => {
            const page = btn.getAttribute('data-navigate');
            navigateToPage(page);
        });
    });
}

function navigateToPage(page) {
    // Update active states
    document.querySelectorAll('.nav-link').forEach(link => {
        link.classList.remove('active');
        if (link.getAttribute('data-page') === page) {
            link.classList.add('active');
        }
    });

    // Show/hide pages
    document.querySelectorAll('.page').forEach(p => {
        p.classList.remove('active');
    });
    document.getElementById(page).classList.add('active');

    state.currentPage = page;

    // Update content when navigating to specific pages
    if (page === 'dashboard') {
        updateDashboard();
    } else if (page === 'wardrobe') {
        renderWardrobe();
    } else if (page === 'recommendations') {
        renderOutfits();
    }
}

// Wardrobe Upload
function initializeWardrobeUpload() {
    const uploadArea = document.getElementById('upload-area');
    const fileInput = document.getElementById('file-input');
    const uploadBtn = document.getElementById('upload-btn');

    uploadBtn.addEventListener('click', () => {
        fileInput.click();
    });

    uploadArea.addEventListener('click', (e) => {
        if (e.target !== uploadBtn) {
            fileInput.click();
        }
    });

    fileInput.addEventListener('change', handleFileSelect);

    // Drag and drop
    uploadArea.addEventListener('dragover', (e) => {
        e.preventDefault();
        uploadArea.classList.add('drag-over');
    });

    uploadArea.addEventListener('dragleave', () => {
        uploadArea.classList.remove('drag-over');
    });

    uploadArea.addEventListener('drop', (e) => {
        e.preventDefault();
        uploadArea.classList.remove('drag-over');
        const files = e.dataTransfer.files;
        handleFiles(files);
    });
}

function handleFileSelect(e) {
    const files = e.target.files;
    handleFiles(files);
}

function handleFiles(files) {
    if (files.length === 0) return;

    // Check premium limits
    if (!state.isPremium && state.wardrobe.length + files.length > 50) {
        showToast('❌ Free plan limit: 50 items. Upgrade to Premium for unlimited items!');
        openPremiumModal();
        return;
    }

    Array.from(files).forEach(file => {
        if (file.type.startsWith('image/')) {
            const reader = new FileReader();
            reader.onload = (e) => {
                const item = {
                    id: Date.now() + Math.random(),
                    name: file.name.split('.')[0],
                    image: e.target.result,
                    category: detectCategory(), // Mock AI detection
                    uploadDate: new Date()
                };
                state.wardrobe.push(item);
                saveToLocalStorage();
                renderWardrobe();
                updateDashboard();
                showToast(`✅ Added ${item.name} to wardrobe`);
            };
            reader.readAsDataURL(file);
        }
    });
}

// Mock AI category detection
function detectCategory() {
    return clothingCategories[Math.floor(Math.random() * clothingCategories.length)];
}

// Wardrobe Rendering
function initializeFilters() {
    // Category filters
    document.querySelectorAll('.tab-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            state.currentFilter.category = btn.getAttribute('data-category');
            renderWardrobe();
        });
    });

    // Occasion and weather filters
    document.getElementById('occasion-filter').addEventListener('change', (e) => {
        state.currentFilter.occasion = e.target.value;
    });

    document.getElementById('weather-filter').addEventListener('change', (e) => {
        state.currentFilter.weather = e.target.value;
    });

    // Generate outfits button
    document.getElementById('generate-outfits').addEventListener('click', generateOutfits);
}

function renderWardrobe() {
    const grid = document.getElementById('wardrobe-grid');
    const category = state.currentFilter.category;

    const filteredItems = category === 'all' 
        ? state.wardrobe 
        : state.wardrobe.filter(item => item.category === category);

    if (filteredItems.length === 0) {
        grid.innerHTML = `
            <div class="empty-state-large">
                <div class="empty-icon">🧺</div>
                <h3>No items in this category</h3>
                <p>Upload some clothes to get started</p>
            </div>
        `;
        return;
    }

    grid.innerHTML = filteredItems.map(item => `
        <div class="wardrobe-item" data-id="${item.id}">
            <img src="${item.image}" alt="${item.name}" class="wardrobe-item-image">
            <div class="wardrobe-item-info">
                <span class="wardrobe-item-category">${getCategoryIcon(item.category)} ${item.category}</span>
                <div class="wardrobe-item-name">${item.name}</div>
            </div>
        </div>
    `).join('');

    updateStats();
}

function getCategoryIcon(category) {
    const icons = {
        'tops': '👕',
        'bottoms': '👖',
        'shoes': '👟',
        'accessories': '👗'
    };
    return icons[category] || '👔';
}

function updateStats() {
    const stats = {
        tops: state.wardrobe.filter(i => i.category === 'tops').length,
        bottoms: state.wardrobe.filter(i => i.category === 'bottoms').length,
        shoes: state.wardrobe.filter(i => i.category === 'shoes').length,
        accessories: state.wardrobe.filter(i => i.category === 'accessories').length
    };

    document.getElementById('stat-tops').textContent = stats.tops;
    document.getElementById('stat-bottoms').textContent = stats.bottoms;
    document.getElementById('stat-shoes').textContent = stats.shoes;
    document.getElementById('stat-accessories').textContent = stats.accessories;
}

// Outfit Generation
function generateOutfits() {
    if (state.wardrobe.length < 3) {
        showToast('❌ Add at least 3 items to generate outfits');
        return;
    }

    // Check premium limits
    if (!state.isPremium && state.outfits.length >= 5) {
        showToast('❌ Free plan limit: 5 outfits per day. Upgrade to Premium!');
        openPremiumModal();
        return;
    }

    const numOutfits = state.isPremium ? 10 : 3;
    state.outfits = [];

    for (let i = 0; i < numOutfits; i++) {
        const outfit = createRandomOutfit();
        if (outfit) {
            state.outfits.push(outfit);
        }
    }

    renderOutfits();
    showToast(`✨ Generated ${state.outfits.length} outfits!`);
}

function createRandomOutfit() {
    const tops = state.wardrobe.filter(i => i.category === 'tops');
    const bottoms = state.wardrobe.filter(i => i.category === 'bottoms');
    const shoes = state.wardrobe.filter(i => i.category === 'shoes');

    if (tops.length === 0 || bottoms.length === 0 || shoes.length === 0) {
        return null;
    }

    const occasions = ['casual', 'formal', 'sporty', 'evening'];

    return {
        id: Date.now() + Math.random(),
        items: [
            tops[Math.floor(Math.random() * tops.length)],
            bottoms[Math.floor(Math.random() * bottoms.length)],
            shoes[Math.floor(Math.random() * shoes.length)]
        ],
        occasion: occasions[Math.floor(Math.random() * occasions.length)],
        weather: weatherConditions[Math.floor(Math.random() * weatherConditions.length)].type
    };
}

function renderOutfits() {
    const grid = document.getElementById('outfits-grid');

    if (state.outfits.length === 0) {
        grid.innerHTML = `
            <div class="empty-state-large">
                <div class="empty-icon">✨</div>
                <h3>No outfits yet</h3>
                <p>Click "Generate Outfits" to get personalized suggestions</p>
            </div>
        `;
        return;
    }

    grid.innerHTML = state.outfits.map(outfit => `
        <div class="outfit-card">
            <div class="outfit-card-header">
                <div class="outfit-card-title">Outfit ${state.outfits.indexOf(outfit) + 1}</div>
                <div class="outfit-card-badge">${outfit.occasion}</div>
            </div>
            <div class="outfit-card-items">
                ${outfit.items.map(item => `
                    <div class="outfit-card-item">
                        <div class="outfit-card-item-icon">${getCategoryIcon(item.category)}</div>
                        <div class="outfit-card-item-name">${item.name}</div>
                    </div>
                `).join('')}
            </div>
            <div class="outfit-card-actions">
                <button class="btn btn-secondary" onclick="shuffleOutfit(${outfit.id})">🔄 Shuffle</button>
                <button class="btn btn-primary" onclick="saveOutfit(${outfit.id})">💾 Save</button>
            </div>
        </div>
    `).join('');
}

function shuffleOutfit(outfitId) {
    const index = state.outfits.findIndex(o => o.id === outfitId);
    if (index !== -1) {
        const newOutfit = createRandomOutfit();
        if (newOutfit) {
            newOutfit.id = outfitId;
            state.outfits[index] = newOutfit;
            renderOutfits();
            showToast('🔄 Outfit shuffled!');
        }
    }
}

function saveOutfit(outfitId) {
    const outfit = state.outfits.find(o => o.id === outfitId);
    if (outfit) {
        const alreadySaved = state.savedOutfits.some(o => o.id === outfitId);
        if (!alreadySaved) {
            state.savedOutfits.push(outfit);
            saveToLocalStorage();
            showToast('💾 Outfit saved!');
        } else {
            showToast('ℹ️ Outfit already saved');
        }
    }
}

// Dashboard
function updateDashboard() {
    updateStats();
    renderTodayOutfit();
}

function renderTodayOutfit() {
    const display = document.getElementById('dashboard-outfit');

    if (state.wardrobe.length < 3) {
        display.innerHTML = '<p class="empty-state">Upload clothes to get outfit suggestions!</p>';
        return;
    }

    const outfit = createRandomOutfit();
    if (outfit) {
        display.innerHTML = outfit.items.map(item => `
            <div class="outfit-item">
                <div class="outfit-item-icon">${getCategoryIcon(item.category)}</div>
                <div class="outfit-item-info">
                    <div class="outfit-item-name">${item.name}</div>
                    <div class="outfit-item-category">${item.category}</div>
                </div>
            </div>
        `).join('');
    }

    // Shuffle and save buttons
    document.getElementById('shuffle-dashboard').addEventListener('click', () => {
        renderTodayOutfit();
        showToast('🔄 New outfit suggestion!');
    });

    document.getElementById('save-dashboard').addEventListener('click', () => {
        if (outfit) {
            state.savedOutfits.push(outfit);
            saveToLocalStorage();
            showToast('💾 Outfit saved!');
        }
    });
}

function setRandomWeather() {
    const weather = weatherConditions[Math.floor(Math.random() * weatherConditions.length)];
    document.getElementById('weather-temp').textContent = weather.temp;
    document.getElementById('weather-condition').textContent = weather.condition;
}

// Settings
function initializeSettings() {
    // Load current settings
    document.getElementById('location-input').value = state.settings.location;
    document.getElementById('sustainability-mode').checked = state.settings.sustainabilityMode;
    document.getElementById('affiliate-mode').checked = state.settings.affiliateMode;

    // Style preferences
    document.querySelectorAll('input[name="style"]').forEach(checkbox => {
        checkbox.checked = state.settings.styles.includes(checkbox.value);
    });

    // Save settings button
    document.getElementById('save-settings').addEventListener('click', () => {
        state.settings.location = document.getElementById('location-input').value;
        state.settings.sustainabilityMode = document.getElementById('sustainability-mode').checked;
        state.settings.affiliateMode = document.getElementById('affiliate-mode').checked;

        state.settings.styles = [];
        document.querySelectorAll('input[name="style"]:checked').forEach(checkbox => {
            state.settings.styles.push(checkbox.value);
        });

        saveToLocalStorage();
        showToast('✅ Settings saved!');
    });
}

// Premium Modal
function initializePremiumModal() {
    const modal = document.getElementById('premium-modal');
    const closeBtn = document.getElementById('close-modal');

    // Open modal buttons
    document.getElementById('upgrade-btn').addEventListener('click', openPremiumModal);
    document.getElementById('upgrade-profile-btn').addEventListener('click', openPremiumModal);

    // Close modal
    closeBtn.addEventListener('click', closePremiumModal);
    modal.addEventListener('click', (e) => {
        if (e.target === modal) {
            closePremiumModal();
        }
    });

    // Subscribe button (mock)
    document.getElementById('subscribe-btn').addEventListener('click', () => {
        showToast('🌟 Premium subscription activated! (Demo mode)');
        state.isPremium = true;
        saveToLocalStorage();
        closePremiumModal();
        updateAccountStatus();
    });
}

function openPremiumModal() {
    document.getElementById('premium-modal').classList.add('active');
}

function closePremiumModal() {
    document.getElementById('premium-modal').classList.remove('active');
}

function updateAccountStatus() {
    const badge = document.querySelector('.account-badge');
    const info = document.querySelector('.account-info p');
    const upgradeBtn = document.getElementById('upgrade-profile-btn');

    if (state.isPremium) {
        badge.textContent = 'Premium';
        badge.style.background = 'linear-gradient(135deg, #4CAF50, #7BC67E)';
        badge.style.color = 'white';
        info.textContent = 'Unlimited outfit combinations';
        upgradeBtn.style.display = 'none';
    }
}

// Toast Notifications
function showToast(message) {
    const toast = document.getElementById('toast');
    toast.textContent = message;
    toast.classList.add('show');

    setTimeout(() => {
        toast.classList.remove('show');
    }, 3000);
}

// Local Storage
function saveToLocalStorage() {
    localStorage.setItem('smartfit-state', JSON.stringify(state));
}

function loadFromLocalStorage() {
    const saved = localStorage.getItem('smartfit-state');
    if (saved) {
        const loadedState = JSON.parse(saved);
        Object.assign(state, loadedState);
        updateAccountStatus();
    }
}

// Make functions globally accessible
window.shuffleOutfit = shuffleOutfit;
window.saveOutfit = saveOutfit;
