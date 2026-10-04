"""Synthetic offline inputs only; never a deployable site manifest."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('garden',Path(__file__).with_name('prepare.py'))
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

def fixture():
    return {'project':'garden','owner':'test-controller','pool':'pool','private_network':'private','private_cidr':'10.20.0.0/24',
            'addresses':{a:'10.20.0.'+str(10+i) for i,a in enumerate(m.APPS)},'domain':'garden.internal',
            'hosts':{a:a+'.garden.internal' for a in ('auth','grafana','ai','pi')},
            'lan':{'nictype':'bridged','parent':'testlan','hwaddr':'02:00:00:00:00:01'},'gpu_pci':'0000:03:00.0',
            'incus_metrics':{'target':'10.20.0.1:8443','server_name':'10.20.0.1'},
            'images':{a:{'fingerprint':hashlib.sha256(a.encode()).hexdigest(),'platform':'linux/amd64','source':m.PINS.get(a,'images:debian/13/cloud')} for a in m.APPS},
            'pi':{'cpu':2,'memory':'2GiB','root_size':'10GiB'}}

class Preparation(unittest.TestCase):
    def test_full_state_and_determinism(self):
        with tempfile.TemporaryDirectory() as d:
            d=Path(d);p=d/'site.json';p.write_text(json.dumps(fixture()))
            for name in ('one','two'):m.prepare(m.inputs(p),d/name)
            self.assertEqual({p.name:p.read_bytes() for p in (d/'one').iterdir()},{p.name:p.read_bytes() for p in (d/'two').iterdir()})
            self.assertEqual(len(m.ET.parse(d/'one/incus.xml').getroot().findall('instance')),7)
    def test_duplicate_addresses_rejected(self):
        s=fixture();s['addresses']['pi']=s['addresses']['llama'];self.rejected(s)
    def test_placeholder_fingerprint_rejected(self):
        s=fixture();s['images']['caddy']['fingerprint']='a'*64;self.rejected(s)
    def test_unreviewed_image_rejected(self):
        s=fixture();s['images']['llama']['source']='some-other-image';self.rejected(s)
    def test_duplicate_hosts_rejected(self):
        s=fixture();s['hosts']['pi']=s['hosts']['ai'];self.rejected(s)
    def test_missing_installation_input_rejected(self):
        s=fixture();del s['lan'];self.rejected(s)
    def test_cross_application_models_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'state';m.prepare(fixture(),p)
            models=json.loads((p/'pi-models.json').read_text());models['providers']['homelab']['models'][0]['id']='wrong'
            (p/'pi-models.json').write_text(json.dumps(models))
            with self.assertRaises(ValueError):m.validate(p)
    def test_context_mismatch_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'state';m.prepare(fixture(),p)
            models=json.loads((p/'pi-models.json').read_text());models['providers']['homelab']['models'][0]['contextWindow']=4096
            (p/'pi-models.json').write_text(json.dumps(models))
            with self.assertRaises(ValueError):m.validate(p)
    def rejected(self,s):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'site.json';p.write_text(json.dumps(s))
            with self.assertRaises(ValueError):m.inputs(p)

if __name__=='__main__':unittest.main()
