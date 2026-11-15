# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины
VirtualBox 7.2.22, Ubuntu Server 24.04.4 LTS (без графической среды), 2048 МБ RAM,
2 CPU, динамический VDI 25 ГБ. Базовый диск: `D:\UnikProga_5sem\Devops\DudnikDevops\vm\ubuntu2404.vdi`.
Снимки располагаются в каталоге ВМ `D:\UnikProga_5sem\Devops\VirtualBox VMs\devops-vm\Snapshots`.
На Windows временно отключены запуск Hyper-V и VBS для аппаратного режима VT-x VirtualBox.
Исходные настройки сохранены вне репозитория в `.local` рабочей папки.

## 2. Сетевые интерфейсы
| Интерфейс | Тип | Адрес | Назначение |
|---|---|---|---|
| enp0s3 | NAT, DHCP | 10.0.2.15/24 | Интернет и пакеты |
| enp0s8 | Host-only, DHCP | 192.168.56.101/24 | Доступ с Windows и WSL |
Хостовый интерфейс: 192.168.56.1/24. DHCP VirtualBox: .100, пул .101–.254.
В обоих интерфейсах Netplan включён dhcp4. Адрес DHCP перед изменением hosts сверять через `ip -brief address`.

## 3. Правило проброса портов
Адаптер 1, правило ssh: TCP, хост 127.0.0.1:2222, адрес гостя не задан,
порт гостя 2222. На снимке 01-clean-install порт гостя равен 22.

## 4. Учётные записи
- student, UID 1000: пользователь исходной установки, sudo; после hardening SSH-вход запрещён AllowUsers.
- devops, UID 1001: группы devops и sudo, SSH по отдельному ключу Ed25519.
- root: непосредственный SSH-вход запрещён.
В WSL ключ `/root/.ssh/devops_vm`, конфигурация `/root/.ssh/config`:
```
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```
Права `.ssh` сервера 700, `authorized_keys` 600. Секреты и приватные ключи не входят в репозиторий.

## 5. Служба SSH
Порт 2222. Конфигурация `/etc/ssh/sshd_config.d/99-hardening.conf`:
```
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```
Основной файл не изменялся, копия `/etc/ssh/sshd_config.backup`.
Конфликтующее PasswordAuthentication yes в 50-cloud-init.conf закомментировано:
OpenSSH использует первое прочитанное значение, поэтому 99-файл сам по себе его не переопределяет.
`ssh.socket` отключён, `ssh.service` включён.
Перед применением: `sudo sshd -t`; после: `sudo sshd -T` и `sudo ss -tlnp`.
Существующая сессия при изменении сохранена до успешного входа по ключу в новой сессии.

## 6. Правила межсетевого экрана
UFW активен, default deny incoming, allow outgoing; logging medium.
Разрешены TCP 80 и 443; TCP 2222 — LIMIT. Правила также созданы для IPv6.
Правила SSH добавлены до активации UFW. Новое подключение после активации проверено.
Журнал `/var/log/ufw.log` содержит UFW BLOCK при обращении Windows к 192.168.56.101:8080.
В hosts Windows добавлены `192.168.56.101 devops.local kv.devops.local`.
WSL 1 получает эти записи при генерации hosts. FQDN сервера `devops-vm.devops.local`:
`127.0.1.1 devops-vm.devops.local devops-vm` в `/etc/hosts` сервера.

## 7. Снимки состояния
- 01-clean-install: установленная и обновлённая Ubuntu, NAT + Host-only, student и OpenSSH на 22.
- 02-keys-configured: devops + sudo, ключ и проверенный вход; до SSH hardening.
- 03-ssh-hardened: SSH на 2222, root/пароль запрещены; до конфигурации UFW.
Снимки создаются на штатно выключенной ВМ. Живое сохранение в этом окружении не завершилось и было отменено через IProgress.Cancel.

### Восстановление после отката на 01-clean-install
1. В VirtualBox восстановить 01-clean-install, убедиться в пробросе 127.0.0.1:2222 -> guest:22, запустить ВМ.
2. Войти `ssh student@127.0.0.1 -p 2222`. Пароль student хранится локально вне Git; сверить ключ хоста через консоль.
3. `sudo adduser devops`, затем `sudo usermod -aG sudo devops`. Передать публичный ключ `~/.ssh/devops_vm.pub`
   в `/home/devops/.ssh/authorized_keys`; владелец devops, права каталога/файла 700/600.
4. Проверить вход `ssh devops`. Сохранить действующую сессию.
5. Сохранить копию sshd_config и создать 99-hardening.conf из раздела 5; закомментировать PasswordAuthentication yes в 50-cloud-init.conf.
6. `sudo sshd -t`; `sudo systemctl disable --now ssh.socket`; `sudo systemctl enable --now ssh.service`; `sudo systemctl restart ssh`.
7. В VirtualBox изменить порт гостя в правиле ssh на 2222; проверить новое соединение `ssh devops` до закрытия старого.
8. `sudo ufw default deny incoming`; `sudo ufw default allow outgoing`; `sudo ufw limit 2222/tcp`;
   `sudo ufw allow 80/tcp`; `sudo ufw allow 443/tcp`; `sudo ufw --force enable`; `sudo ufw logging medium`.
9. Проверить адрес Host-only и запись hosts; `sudo hostnamectl set-hostname devops-vm`;
   изменить строку 127.0.1.1 в hosts сервера на указанную в разделе 6.
10. Доставить репозиторий, запустить `scripts/audit.sh`; ожидается код 0.

### Проверки аудита
На правильной конфигурации: 6 PASS, 0 FAIL, exit 0.
При временном MaxAuthTries 10: 5 PASS, 1 FAIL, exit 1. После проверки восстановлено 3.

### Очистка оставшихся настроек установщика
После восстановления исходного снимка закомментировать строку `deb ... file:///cdrom` в `/etc/apt/sources.list`.
Сохранить `/usr/sbin/policy-rc.d` под именем `policy-rc.d.installer-backup`: этот временный файл установщика возвращает 101 и запрещает автоматический запуск устанавливаемых служб. Затем устанавливать Nginx.

## 8. Веб-сервер
Пакет nginx 1.24.0-2ubuntu7.19 из репозитория Ubuntu, служба nginx enabled/active.
Конфигурация `/etc/nginx/sites-available/devops-site`, ссылка в sites-enabled.
Стандартная ссылка sites-enabled/default удалена, исходный файл сохранён.
Каталог `/var/www/devops-site` принадлежит devops:devops, права 755; файлы 644.
Главная страница и собственная 404 находятся в `site/` репозитория, сервер получает их через rsync.
HTTP 80 перенаправляется кодом 301 на HTTPS 443; разрешены TLSv1.2/TLSv1.3.
При проверке согласован TLSv1.3, TLS_AES_256_GCM_SHA384.
Сертификат `/etc/ssl/certs/devops.crt`, root:root 644; закрытый ключ
`/etc/ssl/private/devops.key`, root:root 600. Ключ за пределы сервера не копировался.
Создание (срок 365 дней, SAN DNS:devops.local):
```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt \
  -subj '/CN=devops.local' -addext 'subjectAltName=DNS:devops.local'
sudo chmod 600 /etc/ssl/private/devops.key
sudo chmod 644 /etc/ssl/certs/devops.crt
```
Публичный сертификат получен с сервера доверенным каналом SSH/SCP, в WSL: `/root/devops.crt`.
Проверка: `curl --cacert ~/devops.crt -I https://devops.local` — 200 без -k.
subject и issuer сертификата совпадают. Имя проверяется по SAN.
Журналы HTTPS-ресурса: `/var/log/nginx/devops-site.access.log` и `devops-site.error.log`.
HTTP-блок перенаправления использует общий журнал Nginx.
Доставка: `scripts/deploy.sh`, один SSH-сеанс rsync, `--delete --chmod=D755,F644`,
BatchMode=yes и ConnectTimeout=5. `--dry-run` не изменяет сервер.
Незакоммиченные изменения и отсутствие index.html прерывают доставку с exit 1;
после доставки HTTPS проверяется с сертификатом; при недоступности exit 1, при успехе
печатается короткий хеш коммита и exit 0. Пять сценариев проверены.
Аудит проверяет nginx active, nginx -t, запас сертификата не менее 30 дней,
отсутствие world-writable файлов и ключ 600. Для отрицательного теста срока:
`CERT_MIN_SECONDS=63072000 scripts/audit.sh`; для отрицательного теста прав — временно 666 на index.html.
В обоих случаях exit 1; в норме 10 PASS, exit 0. После опытов права 644 восстановлены.
Снимок `04-nginx-https` создан после HTTPS до доставки финального содержимого.
Проверка восстановления после реального отката на 01-clean-install завершилась аудитом 0;
автоматизированное выполнение восстановительных команд заняло 14.86 секунды.
Для воспроизведения веб-настройки после восстановления разделов 1–7:
установить nginx/rsync, создать каталог с владельцем devops, применить
`config/nginx/devops-site.conf`, сгенерировать сертификат приведённой командой,
создать символическую ссылку, проверить `sudo nginx -t && sudo systemctl reload nginx`,
скопировать публичный сертификат и запустить деплой из чистого Git-дерева.
