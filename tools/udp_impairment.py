"""Local UDP relay for repeatable ENet latency/jitter/loss QA. No external traffic."""
import heapq
import random
import selectors
import socket
import threading
import time

class UDPImpairment:
    def __init__(self, host_port, delay_ms=0, jitter_ms=0, loss=0):
        self.host_port=host_port
        self.delay=delay_ms/1000
        self.jitter=jitter_ms/1000
        self.loss=loss
        self.forwarded=0
        self.dropped=0
        self._rng=random.Random(701)
        self._selector=selectors.DefaultSelector()
        self._front=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        self._front.bind(('127.0.0.1',0))
        self._front.setblocking(False)
        self.port=self._front.getsockname()[1]
        self._selector.register(self._front,selectors.EVENT_READ,None)
        self._backends={}
        self._pending=[]
        self._serial=0
        self._stop=threading.Event()
        self._thread=threading.Thread(target=self._run,daemon=True)
        self._thread.start()
    def _schedule(self,sock,data,address=None):
        if self._rng.random()<self.loss:
            self.dropped+=1
            return
        self._serial+=1
        deadline=time.monotonic()+max(0,self.delay+self._rng.uniform(-self.jitter,self.jitter))
        heapq.heappush(self._pending,(deadline,self._serial,sock,data,address))
    def _run(self):
        while not self._stop.is_set():
            for key,_ in self._selector.select(.005):
                try:
                    data,address=key.fileobj.recvfrom(65535)
                    if key.fileobj is self._front:
                        if address not in self._backends:
                            back=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
                            back.connect(('127.0.0.1',self.host_port))
                            back.setblocking(False)
                            self._backends[address]=back
                            self._selector.register(back,selectors.EVENT_READ,address)
                        self._schedule(self._backends[address],data)
                    else:
                        self._schedule(self._front,data,key.data)
                except (BlockingIOError,ConnectionRefusedError):
                    continue
            while self._pending and self._pending[0][0]<=time.monotonic():
                _,_,sock,data,address=heapq.heappop(self._pending)
                try:
                    if address is None: sock.send(data)
                    else: sock.sendto(data,address)
                    self.forwarded+=1
                except OSError:
                    pass
    def close(self):
        self._stop.set()
        self._thread.join(2)
        self._selector.close()
        self._front.close()
        for sock in self._backends.values():sock.close()
