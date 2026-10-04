#!/usr/bin/env python3
"""Prepare this specific seven-workload garden from reviewed public installation inputs.
No private values, remote calls, general template engine or production defaults.
"""
import configparser
import ipaddress
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
APPS = ('caddy', 'authelia', 'grafana', 'prometheus', 'llama', 'openwebui', 'pi')
PINS = {
 'caddy': 'docker.io/library/caddy@sha256:13b7fbadd017b042956fddbceedeeea12bb1e560534f9b3df281269dbcc61813',
 'authelia': 'docker.io/authelia/authelia@sha256:bd97cff4fcbf715b5ff1f9ae286afbe6033afce385302520b0368122d43a6f54',
 'grafana': 'docker.io/grafana/grafana@sha256:121a7a9ece6dc10b969f1f96eed64b4f07dfac0d0b8abc070f7cb83bbde86f63',
 'prometheus': 'docker.io/prom/prometheus@sha256:69f5241418838263316593f7274a304b095c40bcf22e57272865da91bd60a8ac',
 'llama': 'ghcr.io/ggml-org/llama.cpp@sha256:0689618b6237be0598b1e743e02847bd92e25def66302de9abb0cfeb29ce0aa8',
 'openwebui': 'ghcr.io/open-webui/open-webui@sha256:9591b13f13843c7721c2b8eaf7382846c81b3ffe126526d1888d1fed50c6a33f',
}

def inputs(path):
    s = json.loads(Path(path).read_text())
    required = {'project', 'owner', 'pool', 'private_network', 'private_cidr', 'addresses',
                'domain', 'hosts', 'lan', 'gpu_pci', 'incus_metrics', 'images', 'pi'}
    if set(s) - required - {'smtp', 'ci'} or required - set(s):
        raise ValueError('Public site input keys are missing or unknown')
    for key in ('project', 'owner', 'pool', 'private_network'):
        if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_.-]{0,62}', s[key]):
            raise ValueError('Invalid resource identifier')
    if set(s['addresses']) != set(APPS) or set(s['images']) != set(APPS):
        raise ValueError('Require exactly seven workload addresses and image records')
    net = ipaddress.ip_network(s['private_cidr'])
    ips = [ipaddress.ip_address(s['addresses'][app]) for app in APPS]
    if len(set(ips)) != 7 or any(ip not in net or ip in (net.network_address, net.broadcast_address) or not ip.is_private for ip in ips):
        raise ValueError('Workload addresses must be distinct usable private subnet addresses')
    if set(s['hosts']) != {'auth', 'grafana', 'ai', 'pi'} or len(set(s['hosts'].values())) != 4:
        raise ValueError('Require distinct auth/grafana/ai/pi hosts')
    for host in [s['domain'], *s['hosts'].values()]:
        if not re.fullmatch(r'[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?', host):
            raise ValueError('Invalid public hostname')
    if any(not host.endswith('.' + s['domain']) for host in s['hosts'].values()):
        raise ValueError('All application hosts must be beneath the cookie domain')
    for app, image in s['images'].items():
        fp = image['fingerprint']
        if not re.fullmatch(r'[a-f0-9]{64}', fp) or len(set(fp)) < 4:
            raise ValueError('Unresolved/placeholder image fingerprint')
        if set(image) != {'source', 'platform', 'fingerprint'}:
            raise ValueError('Image record keys must be public provenance only')
        if app == 'pi' and image['source'] != 'images:debian/13/cloud':
            raise ValueError('Pi must use the reviewed Debian cloud image family')
        if app != 'pi' and image.get('source') != PINS[app]:
            if not s.get('ci', {}).get('controlled_llama') or app != 'llama' or image.get('source') != PINS['openwebui']:
                raise ValueError('Image source does not match the reviewed OCI digest')
        if image.get('platform') != 'linux/amd64':
            raise ValueError('Only reviewed linux/amd64 image inputs are supported')
    if not re.fullmatch(r'[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]', s['gpu_pci']):
        raise ValueError('Require full reviewed GPU PCI identity')
    lan = s['lan']
    if set(lan) != {'nictype', 'parent', 'hwaddr'} or lan['nictype'] not in ('bridged', 'macvlan') or not re.fullmatch(r'[a-zA-Z0-9_.-]{1,15}', lan['parent']) or not re.fullmatch(r'(?:[0-9a-f]{2}:){5}[0-9a-f]{2}', lan['hwaddr']):
        raise ValueError('Require explicit LAN attachment and reviewed MAC')
    if set(s['incus_metrics']) != {'target', 'server_name'} or not re.fullmatch(r'[a-zA-Z0-9.:-]+', s['incus_metrics']['target']) or not re.fullmatch(r'[a-zA-Z0-9.:-]+', s['incus_metrics']['server_name']):
        raise ValueError('Require explicit Incus metrics endpoint and certificate identity')
    if set(s['pi']) != {'cpu', 'memory', 'root_size'} or not isinstance(s['pi']['cpu'], int) or s['pi']['cpu'] < 1 or any(not re.fullmatch(r'[1-9][0-9]*(?:MiB|GiB)', s['pi'][key]) for key in ('memory', 'root_size')):
        raise ValueError('Require explicit Pi capacity')
    if 'ci' in s and set(s['ci']) != {'controlled_llama', 'local_ca', 'nameserver'}:
        raise ValueError('Unknown CI substitution')
    return s

def presets():
    p = configparser.ConfigParser(interpolation=None)
    p.read_string('[router]\n' + (ROOT / 'assets/llama/models.ini').read_text())
    models = []
    for name in p.sections():
        if name in ('router', '*'):
            continue
        values = dict(p['*']) | dict(p[name])
        context = int(values['ctx-size']) // int(values['parallel'])
        if context < 32768:
            raise ValueError('Pi requires at least 32768 context tokens per slot')
        models.append({'id': name, 'name': name, 'reasoning': True, 'input': ['text'], 'contextWindow': context,
                       'maxTokens': 8192, 'cost': dict.fromkeys(('input', 'output', 'cacheRead', 'cacheWrite'), 0),
                       'compat': {'supportsDeveloperRole': False, 'supportsStore': False, 'supportsReasoningEffort': False, 'maxTokensField': 'max_tokens'}})
    if [m['id'] for m in models] != ['mimo', 'qwen36']:
        raise ValueError('Unexpected public model IDs')
    return models

def prepare(s, output):
    if 'smtp' in s and (set(s['smtp']) != {'address', 'username', 'sender', 'startup_check_address'} or not all(isinstance(v,str) and v for v in s['smtp'].values())):
        raise ValueError('SMTP inputs must contain only reviewed non-secret fields')
    output = Path(output)
    if output.exists() and any(output.iterdir()):
        raise ValueError('Output must be absent or empty; do not overwrite reviewed state')
    output.mkdir(parents=True, exist_ok=True)
    def write(name, value):
        (output / name).write_text(value if isinstance(value, str) else json.dumps(value, indent=2) + '\n')
    a, h = s['addresses'], s['hosts']
    xml = ET.Element('incus', project=s['project'])
    def config(parent, values):
        c = ET.SubElement(parent, 'config')
        for key, value in values.items():
            ET.SubElement(c, 'entry', key=key, value=str(value))
    def device(instance, name, kind, values):
        config(ET.SubElement(instance, 'device', name=name, type=kind), values)
    def volume(name, uid, gid, mode='0700'):
        config(ET.SubElement(xml, 'volume', pool=s['pool'], name=name), {'security.shifted': 'true', 'initial.uid': uid, 'initial.gid': gid, 'initial.mode': mode})
    def disk(instance, name, source, path, readonly=False):
        device(instance, name, 'disk', {'pool': s['pool'], 'source': source, 'path': path, 'readonly': str(readonly).lower()})
    def public_config(name, filename, target):
        ET.SubElement(ET.SubElement(xml, 'configuration', name=name), 'file', path=target, source=filename)
    def mount(instance, name, source, path, uid, gid, secret=False, mode=None):
        values = {'name': name, 'secret' if secret else 'configuration': source, 'pool': s['pool'], 'path': path, 'uid': str(uid), 'gid': str(gid)}
        if mode:
            values['mode'] = mode
        ET.SubElement(instance, 'mount', values)
    def instance(name, uid, gid, environment, entrypoint=None):
        obj = ET.SubElement(xml, 'instance', name=name, fingerprint=s['images'][name]['fingerprint'])
        if name == 'pi':
            obj.set('type', 'virtual-machine')
        values = {'boot.autostart': 'true', 'boot.autorestart': 'true'}
        if name != 'pi':
            values |= {'oci.uid': uid, 'oci.gid': gid}
        values |= environment
        if entrypoint:
            values['oci.entrypoint'] = entrypoint
        config(obj, values)
        root = {'pool': s['pool'], 'path': '/'}
        if name == 'pi':
            root['size'] = s['pi']['root_size']
        device(obj, 'root', 'disk', root)
        device(obj, 'eth0', 'nic', {'network': s['private_network'], 'name': 'eth0', 'ipv4.address': a[name]})
        return obj
    for name in ('authelia-session', 'authelia-storage', 'authelia-reset', 'authelia-hmac', 'grafana-admin', 'grafana-session', 'webui-session'):
        ET.SubElement(xml, 'secret', name=name)
    ET.SubElement(xml, 'secret', name='oidc-signing', kind='rsa-3072')
    for consumer in ('grafana', 'webui'):
        ET.SubElement(xml, 'secret', name=consumer+'-client', bytes='54')
        ET.SubElement(xml, 'secret', name=consumer+'-hash', kind='pbkdf2-sha512', source=consumer+'-client')
    ET.SubElement(xml, 'volume', {'pool': s['pool'], 'name': 'private-users', 'private-owner': s['owner'], 'private-kind': 'users', 'private-uid': '1000'})
    ET.SubElement(xml, 'volume', {'pool': s['pool'], 'name': 'incus-metrics', 'private-owner': s['owner'], 'private-kind': 'metrics', 'private-uid': '65534'})
    base = {'server': {'address': 'tcp://0.0.0.0:9091/'}, 'log': {'level': 'warn'},
            'authentication_backend': {'file': {'path': '/etc/private-users/users.yml', 'watch': False}},
            'webauthn': {'enable_passkey_login': True, 'selection_criteria': {'discoverability': 'required', 'user_verification': 'required'}},
            'session': {'cookies': [{'domain': s['domain'], 'authelia_url': 'https://'+h['auth'], 'default_redirection_url': 'https://'+h['grafana']}]},
            'storage': {'local': {'path': '/data/db.sqlite3'}},
            'telemetry': {'metrics': {'enabled': True, 'address': 'tcp://0.0.0.0:9959/metrics'}},
            'notifier': {'filesystem': {'filename': '/data/notification.txt'}}}
    if 'smtp' in s:
        if set(s['smtp']) != {'address', 'username', 'sender', 'startup_check_address'} or not all(isinstance(v,str) and v for v in s['smtp'].values()):
            raise ValueError('SMTP inputs must contain only reviewed non-secret fields')
        base['notifier'] = {'smtp': s['smtp']}
        ET.SubElement(xml, 'volume', {'pool': s['pool'], 'name': 'private-smtp', 'private-owner': s['owner'], 'private-kind': 'smtp', 'private-uid': '1000'})
    write('authelia.json', base)
    oidc = '''identity_providers:
  oidc:
    jwks:
      - key: {{ secret "/etc/tend-signing/value" | mindent 10 "|" | msquote }}
        key_id: garden
        algorithm: RS256
        use: sig
    authorization_policies:
      grafana_admins:
        default_policy: deny
        rules:
          - policy: one_factor
            subject: [["group:admins"]]
      ai_users:
        default_policy: deny
        rules:
          - policy: one_factor
            subject: [["group:ai-users"]]
    claims_policies:
      garden:
        id_token: [email, name, groups, preferred_username]
    clients:
'''
    for name, policy, host, callback in [('grafana', 'grafana_admins', h['grafana'], '/login/generic_oauth'), ('webui', 'ai_users', h['ai'], '/oauth/oidc/callback')]:
        oidc += f'''      - client_id: {name}-garden
        client_name: {name}
        client_secret: '{{{{ secret "/etc/tend-{name}-hash/value" }}}}'
        public: false
        authorization_policy: {policy}
        claims_policy: garden
        consent_mode: explicit
        redirect_uris: ["https://{host}{callback}"]
        scopes: [openid, profile, email, groups]
        response_types: [code]
        response_modes: [query]
        grant_types: [authorization_code]
        require_pkce: true
        pkce_challenge_method: S256
        token_endpoint_auth_method: client_secret_basic
        id_token_signed_response_alg: RS256
'''
    write('oidc.yml', oidc)
    write('models.ini', (ROOT/'assets/llama/models.ini').read_text())
    write('webui-start.sh', (ROOT/'assets/openwebui/start.sh').read_text())
    write('incus.json', (ROOT/'assets/grafana/incus.json').read_text())
    write('datasources.json', {'apiVersion':1,'datasources':[{'name':'Prometheus','uid':'prometheus','type':'prometheus','access':'proxy','url':'http://'+a['prometheus']+':9090','isDefault':True,'editable':False}]})
    write('dashboards.json', {'apiVersion':1,'providers':[{'name':'garden','orgId':1,'folder':'Homelab','type':'file','disableDeletion':False,'allowUiUpdates':False,'options':{'path':'/etc/tend-dashboards'}}]})
    issuer = 'https://' + h['auth']
    grafana = f'''[server]
root_url = https://{h['grafana']}
[analytics]
reporting_enabled = false
check_for_updates = false
check_for_plugin_updates = false
[plugins]
preinstall_disabled = true
[auth]
disable_login_form = true
[auth.basic]
enabled = false
[auth.generic_oauth]
enabled = true
name = Authelia
auto_login = true
client_id = grafana-garden
scopes = openid profile email groups
auth_url = {issuer}/api/oidc/authorization
token_url = {issuer}/api/oidc/token
api_url = {issuer}/api/oidc/userinfo
login_attribute_path = preferred_username
groups_attribute_path = groups
allowed_groups = admins
role_attribute_path = contains(groups[*], 'admins') && 'GrafanaAdmin' || 'Viewer'
role_attribute_strict = true
allow_assign_grafana_admin = true
use_pkce = true
auth_style = InHeader
validate_id_token = true
jwk_set_url = {issuer}/jwks.json
[metrics]
enabled = true
[log]
mode = file
level = warn
'''
    if s.get('ci', {}).get('local_ca'):
        grafana += '[auth.generic_oauth]\ntls_client_ca = /etc/garden-ca/root.crt\n'
    write('grafana.ini', grafana)
    models = presets()
    jobs = [{'job_name': name, 'static_configs':[{'targets':[a[name]+':'+port]}]} for name, port in [('prometheus','9090'),('caddy','9180'),('authelia','9959'),('grafana','3000')]]
    jobs += [{'job_name':'incus','scheme':'https','metrics_path':'/1.0/metrics','static_configs':[{'targets':[s['incus_metrics']['target']]}],
              'tls_config':{'ca_file':'/etc/incus-tls/server.crt','cert_file':'/etc/incus-tls/client.crt','key_file':'/etc/incus-tls/client.key','server_name':s['incus_metrics']['server_name']}},
             {'job_name':'llama','metrics_path':'/metrics','params':{'autoload':['false']},'static_configs':[{'targets':[a['llama']+':8080'],'labels':{'model':m['id']}} for m in models], 'relabel_configs':[{'source_labels':['model'],'target_label':'__param_model'}]}]
    write('prometheus.json', {'global':{'scrape_interval':'30s'},'scrape_configs':jobs})
    for name, filename, target in [('auth-base','authelia.json','/configuration.json'),('oidc','oidc.yml','/oidc.yml'),('llama-presets','models.ini','/models.ini'),('webui-launch','webui-start.sh','/start.sh'),('grafana-settings','grafana.ini','/grafana.ini'),('grafana-datasource','datasources.json','/datasources.yml'),('grafana-provider','dashboards.json','/provider.yml'),('grafana-dashboard','incus.json','/incus.json'),('prom-settings','prometheus.json','/prometheus.yml')]:
        public_config(name,filename,target)
    for name, uid, gid, mode in [('caddy-data',0,0,'0700'),('caddy-config',0,0,'0700'),('authelia-data',1000,1000,'0700'),('grafana-data',472,0,'0700'),('prometheus-data',65534,65534,'0700'),('llama-cache',1000,1000,'0750'),('webui-data',0,0,'0700'),('pi-agent',1000,1000,'0700'),('pi-workspace',1000,1000,'0700')]:
        volume(name,uid,gid,mode)
    caddy = instance('caddy',0,0,{'environment.XDG_CONFIG_HOME':'/config','environment.XDG_DATA_HOME':'/data'},'caddy run --config /etc/caddy/Caddyfile --adapter caddyfile')
    device(caddy,'lan','nic', s['lan'] | {'name':'eth1'})
    disk(caddy,'data','caddy-data','/data'); disk(caddy,'config','caddy-config','/config')
    authenv = {'environment.X_AUTHELIA_CONFIG':'/etc/tend-base/configuration.json,/etc/tend-oidc/oidc.yml,/etc/tend-authorization/access-control.json','environment.X_AUTHELIA_CONFIG_FILTERS':'template','environment.AUTHELIA_SESSION_SECRET_FILE':'/etc/tend-session/value','environment.AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE':'/etc/tend-storage/value','environment.AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET_FILE':'/etc/tend-reset/value','environment.AUTHELIA_IDENTITY_PROVIDERS_OIDC_HMAC_SECRET_FILE':'/etc/tend-hmac/value'}
    if 'smtp' in s:
        authenv['environment.AUTHELIA_NOTIFIER_SMTP_PASSWORD_FILE'] = '/etc/private-smtp/password'
    auth = instance('authelia',1000,1000,authenv,'/app/authelia --config /etc/tend-base/configuration.json --config /etc/tend-oidc/oidc.yml --config /etc/tend-authorization/access-control.json')
    disk(auth,'data','authelia-data','/data'); disk(auth,'users','private-users','/etc/private-users',True)
    if 'smtp' in s:
        disk(auth,'smtp','private-smtp','/etc/private-smtp',True)
    mount(auth,'base','auth-base','/etc/tend-base',1000,1000,mode='0644'); mount(auth,'oidc','oidc','/etc/tend-oidc',1000,1000,mode='0644')
    for mountname, secret, path in [('session','authelia-session','session'),('storage','authelia-storage','storage'),('reset','authelia-reset','reset'),('hmac','authelia-hmac','hmac'),('signing','oidc-signing','signing'),('grafana-hash','grafana-hash','grafana-hash'),('webui-hash','webui-hash','webui-hash')]:
        mount(auth,mountname,secret,'/etc/tend-'+path,1000,1000,True)
    graf = instance('grafana',472,0,{'environment.GF_PATHS_CONFIG':'/etc/tend-grafana/grafana.ini','environment.GF_SECURITY_ADMIN_PASSWORD__FILE':'/etc/tend-grafana-admin/value','environment.GF_SECURITY_SECRET_KEY__FILE':'/etc/tend-grafana-session/value','environment.GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET__FILE':'/etc/tend-grafana-client/value'})
    disk(graf,'data','grafana-data','/var/lib/grafana')
    for name, source, path in [('settings','grafana-settings','/etc/tend-grafana'),('datasource','grafana-datasource','/etc/grafana/provisioning/datasources'),('provider','grafana-provider','/etc/grafana/provisioning/dashboards'),('dashboard','grafana-dashboard','/etc/tend-dashboards')]:
        mount(graf,name,source,path,472,0,mode='0644')
    for name in ('client','admin','session'):
        mount(graf,name,'grafana-'+name,'/etc/tend-grafana-'+name,472,0,True)
    prom = instance('prometheus',65534,65534,{})
    disk(prom,'data','prometheus-data','/prometheus');disk(prom,'metrics','incus-metrics','/etc/incus-tls',True)
    mount(prom,'settings','prom-settings','/etc/prometheus',65534,65534,mode='0644')
    llamaenv = {'environment.LLAMA_CACHE':'/var/cache/llama','environment.LLAMA_ARG_MODELS_PRESET':'/etc/llama/models.ini','environment.LLAMA_ARG_MODELS_MAX':'1','environment.LLAMA_ARG_MODELS_AUTOLOAD':'true','environment.LLAMA_ARG_HOST':'0.0.0.0','environment.LLAMA_ARG_PORT':'8080','environment.LLAMA_ARG_ENDPOINT_METRICS':'1','environment.LLAMA_ARG_UI':'false'}
    llama = instance('llama',1000,1000,llamaenv)
    disk(llama,'cache','llama-cache','/var/cache/llama');mount(llama,'settings','llama-presets','/etc/llama',1000,1000,mode='0644')
    if s.get('ci', {}).get('controlled_llama'):
        entry = ET.SubElement(llama.find('config'),'entry',key='oci.entrypoint',value='python3 /etc/llama/llama-protocol.py')
        write('llama-protocol.py',(ROOT/'assets/llama/llama-protocol.py').read_text())
        ET.SubElement(xml.find("configuration[@name='llama-presets']"),'file',path='/llama-protocol.py',source='llama-protocol.py')
    else:
        device(llama,'gpu','gpu',{'gputype':'physical','pci':s['gpu_pci'],'uid':1000,'gid':1000,'mode':'0660'})
        device(llama,'kfd','unix-char',{'source':'/dev/kfd','path':'/dev/kfd','uid':1000,'gid':1000,'mode':'0660'})
    webenv = {'WEBUI_URL':'https://'+h['ai'],'WEBUI_AUTH':'true','WEBUI_SESSION_COOKIE_SECURE':'true','WEBUI_AUTH_COOKIE_SECURE':'true','ENABLE_LOGIN_FORM':'false','ENABLE_PASSWORD_AUTH':'false','ENABLE_SIGNUP':'false','ENABLE_OAUTH_SIGNUP':'true','ENABLE_OAUTH':'true','OAUTH_CLIENT_ID':'webui-garden','OAUTH_PROVIDER_NAME':'Authelia','OPENID_PROVIDER_URL':issuer+'/.well-known/openid-configuration','OPENID_REDIRECT_URI':'https://'+h['ai']+'/oauth/oidc/callback','OAUTH_SCOPES':'openid profile email groups','OAUTH_CODE_CHALLENGE_METHOD':'S256','OAUTH_TOKEN_ENDPOINT_AUTH_METHOD':'client_secret_basic','ENABLE_OAUTH_ROLE_MANAGEMENT':'true','OAUTH_ROLES_CLAIM':'groups','OAUTH_ALLOWED_ROLES':'ai-users','OAUTH_ADMIN_ROLES':'admins','OAUTH_MERGE_ACCOUNTS_BY_EMAIL':'false','ENABLE_PERSISTENT_CONFIG':'false','ENABLE_OAUTH_PERSISTENT_CONFIG':'false','ENABLE_OLLAMA_API':'false','ENABLE_OPENAI_API':'true','OPENAI_API_BASE_URL':'http://'+a['llama']+':8080/v1','CORS_ALLOW_ORIGIN':'https://'+h['ai'],'FORWARDED_ALLOW_IPS':s['private_cidr']}
    webui = instance('openwebui',0,0,{'environment.'+key:value for key,value in webenv.items()},'/bin/sh /etc/tend-webui-launch/start.sh')
    disk(webui,'data','webui-data','/app/backend/data');mount(webui,'launch','webui-launch','/etc/tend-webui-launch',0,0,mode='0555')
    mount(webui,'client','webui-client','/etc/tend-webui-client',0,0,True);mount(webui,'session','webui-session','/etc/tend-webui-session',0,0,True)
    if s.get('ci', {}).get('local_ca'):
        # The bootstrap supplies only a PUBLIC local CA, never a production trust bypass.
        public_config('garden-ca','root.crt','/root.crt')
        for obj,uid,gid in [(graf,472,0),(webui,0,0)]:
            mount(obj,'garden-ca','garden-ca','/etc/garden-ca',uid,gid,mode='0644')
            ET.SubElement(obj.find('config'),'entry',key='environment.SSL_CERT_FILE',value='/etc/garden-ca/root.crt')
        ET.SubElement(webui.find('config'),'entry',key='environment.REQUESTS_CA_BUNDLE',value='/etc/garden-ca/root.crt')
        for obj in (graf,webui):
            ET.SubElement(obj.find('config'),'entry',key='oci.dns.nameservers',value=s['ci']['nameserver'])
        ET.SubElement(webui.find('config'),'entry',key='environment.OFFLINE_MODE',value='true')
    pi_models = {'providers':{'homelab':{'baseUrl':'http://'+a['llama']+':8080/v1','api':'openai-completions','apiKey':'local-no-secret','models':models}}}
    write('pi-models.json',pi_models)
    def cloud_file(path,content,permissions='0444'):
        return dict(path=path,content=content,owner='root:root',permissions=permissions)
    cloud = {'package_update':True,'package_upgrade':True,'packages':['ca-certificates','curl','xz-utils','ripgrep','fd-find','git','unattended-upgrades'],
             'users':[dict(name='pi',uid=1000,lock_passwd=True,shell='/usr/sbin/nologin',no_create_home=True)],
             'write_files':[cloud_file('/opt/homelab-pi/install.sh',(ROOT/'assets/pi/install.sh').read_text().replace('${release_ref}','build-de8c7c683751d0bd91d6e92a8b5f9ea8497f39de').replace('${archive_sha256}','7b004aaf4be27d0b1e8ad0860c3897fe66d701f28c67e5982f01417744f0756b')),
                            cloud_file('/etc/systemd/system/homelab-pi.service',(ROOT/'assets/pi/pi.service').read_text()),cloud_file('/etc/homelab-pi/models.json',json.dumps(pi_models)),
                            cloud_file('/etc/homelab-pi/service.env','PI_PROVIDER=homelab\nPI_WEB_UI_ORIGIN=https://'+h['pi']+'\nPI_MODEL_ID=mimo\n'),
                            cloud_file('/etc/apt/apt.conf.d/20auto-upgrades','APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n','0644')],
             'runcmd':[['/bin/sh','/opt/homelab-pi/install.sh']]}
    userdata = '#cloud-config\n'+json.dumps(cloud,indent=2)+'\n'
    write('pi-cloud-init.yml',userdata)
    pi = instance('pi',1000,1000,{'limits.cpu':s['pi']['cpu'],'limits.memory':s['pi']['memory'],'cloud-init.user-data':userdata})
    disk(pi,'agent','pi-agent','/var/lib/pi');disk(pi,'workspace','pi-workspace','/workspace')
    gateway = ET.SubElement(xml,'ingress-gateway',{'instance':'caddy','pool':s['pool'],'path':'/etc/caddy','authorization-instance':'authelia','authorization-device':'eth0','authorization-path':'/etc/tend-authorization','authorization-uid':'1000','authorization-gid':'1000'})
    ET.SubElement(gateway,'metrics',device='eth0')
    for name, app, port in [('auth','authelia',9091),('grafana','grafana',3000),('ai','openwebui',8080),('pi','pi',3001)]:
        route = ET.SubElement(xml,'ingress',{'name':name,'host':h[name],'instance':app,'device':'eth0','port':str(port)})
        if name == 'pi':
            ET.SubElement(ET.SubElement(route,'authorization',policy='one_factor'),'group',name='ai-users')
        else:
            ET.SubElement(route,'public')
    order = {name:i for i,name in enumerate(('secret','configuration','volume','instance','ingress-gateway','ingress','egress'))}
    xml[:] = sorted(xml, key=lambda child:order[child.tag])
    for obj in xml.findall('instance'):
        obj[:] = sorted(obj, key=lambda child:('config','device','mount').index(child.tag))
    ET.indent(xml)
    write('incus.xml',ET.tostring(xml,encoding='unicode')+'\n')
    write('installation.json',s)
    write('provenance.json',{'baseline':'8fc54492c6d75d9713061703c5a6667347e1481b','images':s['images'],'substitutions':s.get('ci',{}),'models':models})
    validate(output)

def validate(output):
    output=Path(output)
    x=ET.parse(output/'incus.xml').getroot()
    names={i.get('name') for i in x.findall('instance')}
    if names != set(APPS):
        raise ValueError('Prepared state must contain all seven workloads')
    ips=[d.find("config/entry[@key='ipv4.address']").get('value') for d in x.findall("instance/device[@name='eth0']")]
    if len(set(ips)) != 7:
        raise ValueError('Duplicate workload IP')
    for f in x.findall('configuration/file'):
        if not (output/f.get('source')).is_file():
            raise ValueError('Missing public configuration file')
    model_ids={m['id'] for m in json.loads((output/'pi-models.json').read_text())['providers']['homelab']['models']}
    scrape=json.loads((output/'prometheus.json').read_text())['scrape_configs'][-1]
    if model_ids != {t['labels']['model'] for t in scrape['static_configs']} or model_ids != {m['id'] for m in presets()}:
        raise ValueError('Cross-application model IDs disagree')
    if [m['contextWindow'] for m in json.loads((output/'pi-models.json').read_text())['providers']['homelab']['models']] != [m['contextWindow'] for m in presets()]:
        raise ValueError('Pi context-per-slot disagrees with presets')

if __name__ == '__main__':
    try:
        if len(sys.argv) == 3 and sys.argv[1] == '--validate':
            validate(sys.argv[2])
        elif len(sys.argv) == 3:
            prepare(inputs(sys.argv[1]),sys.argv[2])
        else:
            raise ValueError('Usage: prepare.py PUBLIC_SITE_JSON EMPTY_OUTPUT | --validate OUTPUT')
    except (ValueError,KeyError,OSError) as error:
        print('Garden preparation rejected: '+str(error),file=sys.stderr)
        sys.exit(1)
