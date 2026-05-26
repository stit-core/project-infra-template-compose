---
name: ansible-style
description: Инварианты ansible-bootstrap нового VPS — идемпотентность тасков (re-run safe), один концерн = одна роль (base/ssh-hardening/docker/stit-onboard), assert required-vars в pre_tasks, секреты НЕ в playbook'е (оператор кладёт .env руками), fail-fast перед disable password auth. Грузится при работе с ansible/.
paths:
  - "ansible/**"
---

# Ansible style

## Идемпотентность

Все таски обязаны быть re-run safe. `apt install` через `ansible.builtin.apt` (а не `command: apt-get install`). Создание файлов — `copy`/`template` с `creates:` или явным content-check. Если задача меняет состояние при повторном запуске без надобности — она сломана, чини.

## Границы ролей

| Роль | Что |
|---|---|
| `base` | Системные пакеты, swap, timezone, базовый sysctl |
| `ssh-hardening` | Disable password auth, root login policy, fail2ban-style |
| `docker` | Docker engine + compose plugin, daemon.json (log driver, log rotation) |
| `stit-onboard` | Клонирование `<client-org>/infra`, deploy-key вывод, директории `/opt/<project>-infra` |

Правило: один концерн = одна роль. Если в `base` появляется что-то про docker — переноси в `docker`.

## Required vars и assertions

`pre_tasks` в playbook'е обязан проверять `assert` на required переменные (`project_name`, `project_repo_url`, `ansible_host`). Без этого playbook молча отработает с пустыми и сломается на полпути.

```yaml
- name: Verify required vars
  ansible.builtin.assert:
    that:
      - project_name is defined
      - project_repo_url is defined
    fail_msg: "Set project_name + project_repo_url in inventory."
```

## Секреты

- **Не клади** реальные секреты в task definitions / `vars:`. Bootstrap не должен знать `VAULT_SECRET_ID` — это даёт оператор руками после `new-env.sh`.
- Если когда-то понадобится — ansible-vault или (лучше) keep-out-of-ansible: оператор кладёт `.env` руками, playbook только разворачивает скелет.
- `authorized_keys` — через файл, не inline. Templates с inline-keys ведут к мерж-конфликтам и непрозрачности.

## Fail-fast

`ssh-hardening` роль **обязана** проверить что у root есть валидные `authorized_keys` ДО того как disable password auth. Иначе можно залочиться с VPS.

```yaml
- name: Ensure root authorized_keys exists and non-empty
  ansible.builtin.stat:
    path: /root/.ssh/authorized_keys
  register: ak

- name: Refuse to harden ssh without authorized_keys
  ansible.builtin.fail:
    msg: "Root has no authorized_keys — refusing to disable password auth."
  when: not ak.stat.exists or ak.stat.size == 0
```

Аналогично для firewall-роли (если появится) — не закрывай порт SSH без проверки что новый порт уже слушается.

## Tags

Каждая роль имеет тег с именем роли (`tags: [base]`, `tags: [docker]`). Это позволяет re-run'ить часть playbook'а: `--tags onboard` после регистрации deploy-key.

## Хост-локальные пути

`/opt/<project>-infra` — стандартное место. Не разбрасывай по `/srv/`, `/var/lib/<project>/` и т.п. Один путь, прописан в `vars: project_root`.

## После правки

- Synth-проверка: `ansible-playbook --syntax-check bootstrap.yml`.
- Dry-run: `ansible-playbook --check -i inventory.ini bootstrap.yml` (если задачи поддерживают check-mode).
- Реальный прогон — на тестовом VPS, не на live.
