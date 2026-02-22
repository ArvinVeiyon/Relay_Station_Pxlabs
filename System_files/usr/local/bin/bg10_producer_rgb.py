#!/usr/bin/env python3
import os, subprocess, numpy as np
W,H=int(os.getenv("W","640")),int(os.getenv("H","480"))
FIFO=os.getenv("FIFO","/tmp/rgb.fifo")
BLACK=int(os.getenv("BLACK","24")); GAIN=float(os.getenv("GAIN","2.0"))
GAMMA=float(os.getenv("GAMMA","2.3"))
WB_R=float(os.getenv("WB_R","1.25")); WB_G=float(os.getenv("WB_G","1.00")); WB_B=float(os.getenv("WB_B","1.15"))
FRAME=W*H*2
def lin(x): return np.clip((x-BLACK)*(GAIN*255.0/max(1.0,1023-BLACK)),0,255)
def gamma(x): return np.clip((x/255.0)**(1.0/GAMMA)*255.0,0,255)
def demosaic_rggb(u16):
    R=u16[0::2,0::2]; G=(u16[0::2,1::2]+u16[1::2,0::2])/2; B=u16[1::2,1::2]
    Rf=np.repeat(np.repeat(R,2,0),2,1)[:H,:W]
    Gf=np.repeat(np.repeat(G,2,0),2,1)[:H,:W]
    Bf=np.repeat(np.repeat(B,2,0),2,1)[:H,:W]
    R8=gamma(lin(Rf)*WB_R); G8=gamma(lin(Gf)*WB_G); B8=gamma(lin(Bf)*WB_B)
    return np.dstack([R8,G8,B8]).astype(np.uint8)
def main():
    with open(FIFO,'wb',buffering=0) as out:
        p=subprocess.Popen(["v4l2-ctl","-d","/dev/video0","--stream-mmap=3","--stream-count=0","--stream-to=-"],
                           stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,bufsize=0)
        rd=p.stdout.read
        while True:
            buf=bytearray()
            while len(buf)<FRAME:
                chunk=rd(FRAME-len(buf))
                if not chunk: return
                buf+=chunk
            u16=np.frombuffer(buf,dtype='<u2').reshape(H,W)
            out.write(demosaic_rggb(np.minimum(u16,1023)).tobytes())
if __name__=="__main__": main()
