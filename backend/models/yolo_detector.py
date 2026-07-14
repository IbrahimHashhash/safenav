import torch
from ultralytics import YOLO

class YOLODetector:
    def __init__(self, variant='yolo11s', device='cuda'):
        self.model = YOLO(f'{variant}.pt')
        self.model.to(device)
        self.device = device

    def warm_up(self, input_size=512):
        dummy = torch.zeros(1, 3, input_size, input_size).to(self.device)
        for _ in range(3): self.model(dummy, verbose=False)

    def detect(self, frame, imgsz=512, conf=0.5):
        return self.model(frame, imgsz=imgsz, conf=conf, verbose=False)
