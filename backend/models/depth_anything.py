import torch
import cv2
import numpy as np
from depth_anything_v2.dpt import DepthAnythingV2

class DepthAnythingModel:
    def __init__(self, variant='vitb', device='cuda', max_depth=80):
        self.device = device
        self.configs = {
            'vitl': {'encoder': 'vitl', 'features': 256, 'out_channels': [256, 512, 1024, 1024], 'checkpoint': 'checkpoints/depth_anything_v2_metric_vkitti_vitl.pth'},
            'vitb': {'encoder': 'vitb', 'features': 128, 'out_channels': [96, 192, 384, 768], 'checkpoint': 'checkpoints/depth_anything_v2_metric_vkitti_vitb.pth'},
            'vits': {'encoder': 'vits', 'features': 64, 'out_channels': [48, 96, 192, 384], 'checkpoint': 'checkpoints/depth_anything_v2_metric_vkitti_vits.pth'}
        }
        cfg = self.configs[variant]
        self.model = DepthAnythingV2(
            encoder=cfg['encoder'], 
            features=cfg['features'], 
            out_channels=cfg['out_channels'], 
            max_depth=max_depth
        )
        self.model.load_state_dict(torch.load(cfg['checkpoint'], map_location='cpu'))
        self.model = self.model.to(device).eval()
        if device == 'cuda':
            self.model = self.model.half() # FP16 half-precision for ~1.5× GPU speedup

    def warm_up(self): # eliminates first-frame latency
        dummy = torch.zeros(1, 3, 308, 308).to(self.device)
        if self.device == 'cuda':
            dummy = dummy.half()
        with torch.inference_mode():
            for _ in range(3): _ = self.model(dummy)

    def infer(self, bgr_frame, input_size=518):
        img = cv2.cvtColor(bgr_frame, cv2.COLOR_BGR2RGB)
        img = cv2.resize(img, (input_size, input_size))
        tensor = torch.from_numpy(img).permute(2, 0, 1).float() / 255.0
        mean = torch.tensor([0.485, 0.456, 0.406]).view(3, 1, 1)
        std  = torch.tensor([0.229, 0.224, 0.225]).view(3, 1, 1)
        tensor = (tensor - mean) / std
        tensor = tensor.unsqueeze(0).to(self.device)
        if self.device == 'cuda':
            tensor = tensor.half()
        with torch.inference_mode():
            depth = self.model(tensor)
        depth = depth.squeeze().float().cpu().numpy()
        return cv2.resize(depth, (bgr_frame.shape[1], bgr_frame.shape[0]), interpolation=cv2.INTER_LINEAR)
