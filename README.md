<div align="center">

# SafeNav 🧭

### AI-Powered Real-Time Navigation Assistance

[![Python](https://img.shields.io/badge/Python-3.8+-blue.svg)](https://www.python.org/downloads/)
[![Flutter](https://img.shields.io/badge/Flutter-3.11.3+-02569B.svg)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.111+-009688.svg)](https://fastapi.tiangolo.com)
[![PyTorch](https://img.shields.io/badge/PyTorch-2.0+-EE4C2C.svg)](https://pytorch.org/)
[![YOLO11](https://img.shields.io/badge/YOLO-11-00FFFF.svg)](https://github.com/ultralytics/ultralytics)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

**[Features](#-features) • [Demo](#-demo) • [Getting Started](#-getting-started) • [Architecture](#-architecture) • [Documentation](#-api-reference)**

</div>

---

## 📖 Overview

SafeNav is an intelligent navigation assistance system designed to help users navigate safely through their environment using AI-powered computer vision. By combining state-of-the-art object detection (YOLO11), monocular depth estimation (Depth-Anything-V2), and real-time voice guidance, SafeNav provides instant spatial awareness and navigation instructions.

**Perfect for:** Accessibility applications, assistive technology research, autonomous navigation systems, and computer vision projects.

## 🌟 Features

- **Real-time Obstacle Detection**: Powered by YOLO11 for fast and accurate object detection
- **Depth Estimation**: Uses Depth-Anything-V2 for precise distance measurement
- **Smart Navigation**: Analyzes free zones and provides optimal path suggestions
- **Voice Guidance**: Text-to-speech navigation instructions with Azure Speech Services
- **Cross-Platform Mobile App**: Built with Flutter for iOS and Android
- **Low-Latency Processing**: WebSocket-based communication for real-time feedback
- **Calibrated Distance Estimation**: Per-object-class depth calibration for improved accuracy

## 🎬 Demo

### How SafeNav Works

SafeNav processes camera frames in real-time to detect obstacles and provide navigation guidance:

1. **Visual Detection**: Camera captures environment
2. **AI Processing**: YOLO11 identifies objects, Depth-Anything-V2 estimates distances
3. **Navigation Analysis**: Algorithm analyzes free zones and calculates safe paths
4. **Voice Feedback**: Natural language instructions guide the user

**Example Output:**
```
"car ahead 3.0 m — left clear"
"person on slight right 2.5 m — proceed straight"
"bench ahead 1.5 m — move right"
```

*Screenshots and video demos coming soon*

## 🏗️ Architecture

SafeNav consists of two main components:

### Backend (Python/FastAPI)
- **AI Pipeline**: YOLO11 + Depth-Anything-V2
- **FastAPI Server**: High-performance WebSocket server
- **Real-time Processing**: GPU-accelerated inference with frame skipping optimization
- **Navigation Logic**: Free-zone analysis and pathfinding algorithms

### Mobile App (Flutter)
- **Cross-platform**: iOS and Android support
- **Camera Integration**: Real-time video capture and streaming
- **Voice Interface**: Azure STT/TTS for hands-free operation
- **Location Services**: GPS integration for contextual awareness

## 🚀 Getting Started

### Prerequisites

- Python 3.8+
- Flutter 3.11.3+
- CUDA-capable GPU (recommended for backend)
- Azure Speech Services account (for voice features)

### Backend Setup

```bash
cd backend

# Install dependencies
pip install -r requirements.txt

# Set environment variables (optional)
export DAV2_VARIANT=vitb
export YOLO_VARIANT=yolo11s
export YOLO_CONF=0.50

# Run the server
python main.py
```

The server will start on `http://localhost:8000` with WebSocket endpoint at `ws://localhost:8000/ws`

### Mobile App Setup

```bash
cd mobile/safenav_app

# Install dependencies
flutter pub get

# Create .env file with your Azure credentials
echo "AZURE_SPEECH_KEY=your_key_here" > .env
echo "AZURE_SPEECH_REGION=your_region" >> .env

# Run the app
flutter run
```

## 🔧 Configuration

### Backend Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DAV2_VARIANT` | `vitb` | Depth-Anything-V2 model variant (vits/vitb/vitl) |
| `DAV2_INPUT_SIZE` | `392` | Input resolution for depth model |
| `YOLO_VARIANT` | `yolo11s` | YOLO model variant |
| `YOLO_INPUT_SIZE` | `512` | Input resolution for YOLO |
| `YOLO_CONF` | `0.50` | Confidence threshold for detections |
| `FRAME_SKIP` | `1` | Enable frame skipping optimization |

### Detected Obstacle Classes

By default, SafeNav detects:
- People
- Cars
- Benches
- Stairs (using separate detector)

## 📡 API Reference

### WebSocket Protocol

**Client → Server (Binary)**
```
[4 bytes: frame_id][1 byte: flags][JPEG image data]
```

**Server → Client (JSON)**
```json
{
  "instruction": "car ahead 3.0 m — left clear",
  "obstacles": [...],
  "free_zones": {...},
  "metrics": {...}
}
```

## 🧠 How It Works

1. **Video Capture**: Mobile app captures camera frames
2. **Frame Transmission**: Frames sent to backend via WebSocket
3. **AI Processing**: 
   - YOLO detects obstacles in the frame
   - Depth-Anything estimates distance to each pixel
   - Per-obstacle depth is calculated and calibrated
4. **Navigation Analysis**: Free zones are analyzed to find safe paths
5. **Guidance Generation**: Natural language instructions are generated
6. **Voice Output**: Instructions spoken to user via TTS

## 📊 Performance

- **Inference Time**: ~50-100ms per frame (on GPU)
- **End-to-end Latency**: <200ms with frame skipping
- **Frame Skipping**: Reduces redundant processing by up to 50%
- **Distance Accuracy**: ±0.3m after calibration

## 🛠️ Technology Stack

**Backend:**
- FastAPI - Web framework
- PyTorch - Deep learning
- OpenCV - Image processing
- Ultralytics YOLO11 - Object detection
- Depth-Anything-V2 - Monocular depth estimation

**Mobile:**
- Flutter - UI framework
- Flutter BLoC - State management
- Azure Speech SDK - Voice services
- Geolocator - Location services

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👤 Developers

- **Ibrahim** 
- **Mays**
- **Raheeq**

## 🔮 Future Roadmap

- [ ] Indoor navigation and mapping
- [ ] Multi-language support
- [ ] Offline mode with on-device inference
- [ ] Augmented reality overlay
- [ ] Community-sourced obstacle database
- [ ] Wearable device integration

---


