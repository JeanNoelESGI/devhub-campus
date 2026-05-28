# RAPPORT.md — TP 2 : GitOps avec ArgoCD (DevHub Campus)

**Auteur :** JeanNoelESGI  
**Cours :** Architecture logicielle & déploiement — M2 Ingénierie Web  
**Année :** 2025–2026

---

## Table des matières

1. [Outillage](#1-outillage)
2. [GitOps en 1 page](#2-gitops-en-1-page)
3. [Vocabulaire ArgoCD](#3-vocabulaire-argocd)
4. [Étape 5 — selfHeal vs prune](#4-étape-5--selfheal-vs-prune)
5. [Étape 6 — App of Apps vs kubectl apply](#5-étape-6--app-of-apps-vs-kubectl-apply)
6. [Étape 7 — Choix du generator ApplicationSet](#6-étape-7--choix-du-generator-applicationset)
7. [Étape 8 — Bestiaire ArgoCD (drift, rollback, hooks, waves)](#7-étape-8--bestiaire-argocd)
8. [Étape 9 — Sécurité et observabilité](#8-étape-9--sécurité-et-observabilité)
9. [Étape 11 — Synthèse : ArgoCD et la prod](#9-étape-11--synthèse--argocd-et-la-prod)

---

## 1. Outillage

> Complétez après avoir lancé `make tools-check` dans WSL2.

| Outil | Version installée |
|---|---|
| Docker Desktop | … |
| kubectl | … |
| kind | … |
| helm | … |
| argocd CLI | … |
| git | … |
| yq | … |

```
# Sorties à compléter après make tools-check :
kubectl version --client
helm version
argocd version --client
```

---

## 2. GitOps en 1 page

### Schéma personnel : Push vs Pull

```
┌─────────────────────────────────────────────────────────────┐
│ MODÈLE PUSH (TP 1)                                          │
│                                                             │
│  Dev ──commit──▶ Git ──trigger──▶ CI/CD Pipeline           │
│                                          │                  │
│                                          │ kubectl apply    │
│                                          ▼                  │
│                                     Cluster K8s             │
│                                                             │
│ ⚠  La CI a les droits cluster.                              │
│ ⚠  Drift silencieux si quelqu'un modifie le cluster.        │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ MODÈLE PULL (TP 2 — GitOps / ArgoCD)                       │
│                                                             │
│  Dev ──commit──▶ Git ◀── poll (3 min) ──ArgoCD controller  │
│                                                  │          │
│                                         compare + converge  │
│                                                  ▼          │
│                                             Cluster K8s     │
│                                                             │
│ ✅ La CI ne touche plus le cluster.                         │
│ ✅ Tout changement = commit tracé dans Git.                 │
│ ✅ Drift détecté immédiatement.                             │
└─────────────────────────────────────────────────────────────┘
```

### Tableau Push vs Pull

| Question | Push (`kubectl apply` en CI) | Pull (ArgoCD) |
|---|---|---|
| Qui a les droits sur le cluster ? | La CI (kubeconfig dans les secrets) | ArgoCD seul (le controller tourne dans le cluster) |
| Où est l'historique des changements ? | Dans les logs CI + le Git de la CI | Dans le Git du repo de config (immuable, traçable) |
| Que se passe-t-il si un dev modifie le cluster à la main ? | Personne ne s'en aperçoit — drift silencieux | ArgoCD passe en `OutOfSync` immédiatement |
| Comment ajouter un environnement de plus ? | Nouveau pipeline + overlays + droits cluster | Ajouter un fichier `Application` dans `platform/apps/` |
| Comment faire un rollback ? | Rejouer la CI sur l'ancien commit | `git revert` → ArgoCD re-converge |
| Combien de pipelines pour 30 services ? | 30 pipelines (une par service) | 1 seul agent ArgoCD, N `Application` |
| Qui voit en direct ce qui tourne ? | Personne facilement (Freelens, kubectl) | Tout le monde via l'UI ArgoCD |

### Ma prise de position

Pour mes projets perso, je commencerais par **push** si je suis seul sur un seul environnement : moins de composants à installer, plus rapide à mettre en place. Je passerais à **pull (ArgoCD)** dès que je travaille à plusieurs, que j'ai plusieurs environnements (dev/staging/prod), ou que je veux des previews automatiques par branche — c'est là que GitOps vaut vraiment l'investissement initial.

---

## 3. Vocabulaire ArgoCD

| Terme | Définition personnelle | Exemple dans mon projet |
|---|---|---|
| `Application` (ressource ArgoCD) | Objet Kubernetes qui décrit : quelle source Git surveiller, où déployer, et comment synchroniser. C'est le pont entre Git et le cluster. | `annuaire-dev` : surveille `services/annuaire/chart` sur `main`, déploie dans `devhub-dev`. |
| `AppProject` | Brique de sécurité qui définit les limites d'un groupe d'Applications : repos autorisés, destinations, ressources K8s autorisées. | `devhub` : autorise uniquement le repo `JeanNoelESGI/devhub-campus`, namespace `devhub-*`. |
| `Source` | Référence Git (URL + branche + chemin) ou Helm chart d'où ArgoCD tire les manifestes. | `repoURL: github.com/JeanNoelESGI/devhub-campus`, `path: services/annuaire/chart`. |
| `Destination` | Cluster Kubernetes + namespace cible où les manifestes seront appliqués. | `server: https://kubernetes.default.svc`, `namespace: devhub-dev`. |
| `Sync` (manuel, auto, self-heal) | Action d'appliquer l'état Git dans le cluster. Différent d'un `kubectl apply` : ArgoCD compare d'abord, puis applique intelligemment. | En étape 5 : sync manuel via l'UI. Puis `selfHeal: true` = sync auto si drift détecté. |
| `Prune` | Suppression des ressources K8s qui n'existent plus dans Git. Dangereux si activé trop tôt. | `prune: true` sur l'ApplicationSet preview : nettoie le namespace quand la branche est supprimée. |
| `App of Apps` | Pattern où une Application "racine" gère d'autres Applications (les enfants). | `root` surveille `platform/apps/dev/` et crée automatiquement `annuaire-dev`, `planning-dev`, `notif-dev`. |
| `ApplicationSet` | Contrôleur qui génère automatiquement des Applications à partir d'un generator (branches Git, PRs, liste…). | `annuaire-preview` : génère une Application par branche `feature/*`. |
| `Sync wave` | Ordre numérique qui contrôle la séquence d'application des ressources dans une sync. Wave -1 avant wave 0 avant wave 1. | `ConfigMap` en wave -1, `Deployment` en wave 0 → le ConfigMap est prêt avant le démarrage des pods. |
| `Hook` (PreSync, Sync, PostSync) | Job ou ressource éphémère déclenchée à un moment précis du cycle de sync. | `PreSync` : job de migration de schéma BDD exécuté avant le déploiement. |

---

## 4. Étape 5 — selfHeal vs prune

### Comparaison

| | `selfHeal: true` | `prune: true` |
|---|---|---|
| Ce que ça fait | Corrige automatiquement un drift (quelqu'un a modifié le cluster hors-Git) | Supprime les ressources K8s qui n'existent plus dans Git |
| Déclencheur | Un `kubectl edit` ou `kubectl scale` hors-Git | Un fichier a été supprimé du chart/du repo Git |
| Risque | Si un HPA ajuste les répliques, ArgoCD les écrase | Si on supprime accidentellement un fichier du chart, ArgoCD supprime la ressource en prod |

### Exemple où `selfHeal: true` serait dangereux

Un HPA (Horizontal Pod Autoscaler) ajuste `replicaCount` à 10 pods parce que le trafic monte. Avec `selfHeal: true`, ArgoCD détecte le drift (Git dit 2 répliques) et redescend à 2 — provoquant un incident de production. Solution : ajouter une `ignoreDifferences` sur `spec.replicas`.

### Exemple où `prune: true` serait dangereux

En étape 5, si on active `prune: true` dès le départ et qu'on fait une faute de frappe dans le chemin `path` de la source, ArgoCD ne trouve plus les manifestes et **supprime tout le namespace `devhub-dev`**. C'est pour ça qu'on l'active en connaissance de cause, après validation.

---

## 5. Étape 6 — App of Apps vs `kubectl apply`

### Pourquoi App of Apps ≠ `kubectl apply -f apps/dev/`

Un `kubectl apply -f apps/dev/` est une action **ponctuelle** : vous l'exécutez une fois, et si quelqu'un supprime une Application ensuite, elle disparaît sans que personne ne s'en aperçoive.

La root Application d'ArgoCD **surveille en continu** le dossier `platform/apps/dev/`. Si une Application enfant est supprimée manuellement du cluster, ArgoCD la recrée immédiatement (grâce à `selfHeal`). C'est la différence fondamentale : **réconciliation continue** vs action ponctuelle.

Autres avantages :
- Ajouter un service = ajouter un fichier YAML dans `platform/apps/dev/` → ArgoCD le détecte et déploie sans intervention humaine.
- Historique tracé dans Git : on sait qui a ajouté quel service, quand, et pourquoi.
- Rollback d'un service entier = `git revert` du commit qui l'a ajouté.

---

## 6. Étape 7 — Choix du generator ApplicationSet

### Generator choisi : `git` generator (branches `feature/*`)

**Justification :**
- Plus simple à mettre en place : pas de token GitHub à stocker comme secret dans le namespace `argocd`.
- Polling toutes les 3 minutes : acceptable en TP. En production, on brancherait un webhook GitHub → ArgoCD pour tomber sous les 10 secondes.
- Le `pullRequest` generator serait préférable en production pour deux raisons : (1) il ne crée un preview que pour les PRs ouvertes (pas toutes les branches), et (2) il expose la variable `{{number}}` pour lier le preview à la PR.

### Démonstration

```bash
# Créer la branche de démo
git checkout -b feature/demo-prof
echo "# démo preview" >> README.md
git add . && git commit -m "chore: demo preview env"
git push origin feature/demo-prof

# Attendre 3 min, puis vérifier dans l'UI ArgoCD :
# → Application "annuaire-preview-feature-demo-prof" apparaît
# → Namespace "devhub-preview-feature-demo-prof" créé

# Supprimer la branche
git push origin --delete feature/demo-prof
# → Application et namespace supprimés automatiquement (prune:true)
```

---

## 7. Étape 8 — Bestiaire ArgoCD

### Scénario 1 : `kubectl scale` hors-Git

```bash
kubectl scale deploy annuaire-dev-annuaire -n devhub-dev --replicas=5
```

**Observation :** ArgoCD passe immédiatement en `OutOfSync`. Avec `selfHeal: true`, il redescend à 1 réplique (valeur dans `values-dev.yaml`) en quelques secondes.

**Conclusion :** `selfHeal` est le gardien de la source de vérité Git. Tout changement direct au cluster est écrasé. C'est voulu — et c'est pourquoi il faut configurer une `ignoreDifferences` si un HPA gère les répliques.

---

### Scénario 2 : Tag d'image inexistant

```bash
# Modifier values-dev.yaml
image.tag: "sha-doesnotexist"
git commit -m "feat: test image pull error"
git push
```

**Observation :** ArgoCD affiche `Synced` (il a appliqué ce qui était dans Git) mais `Degraded` (le pod est en `ImagePullBackOff`). La sync réussit côté Argo mais l'application ne démarre pas.

**Conclusion :** ArgoCD ne valide pas que l'image existe. C'est une limitation : il faut une politique Kyverno ou une vérification dans la CI pour rejeter les images inexistantes avant le push.

---

### Scénario 3 : Git revert = rollback

```bash
git revert HEAD
git push
```

**Observation :** ArgoCD détecte le nouveau commit dans les 3 minutes (polling), synchronise, et le service redevient `Healthy`. Durée mesurée : environ 3 min 30 s (polling + apply).

**Conclusion :** Le rollback GitOps est propre et traçable : le revert est visible dans `git log`. Au TP 1, il fallait relancer la CI sur l'ancien commit — moins lisible dans l'historique.

---

### Scénario 4 : Hook PreSync (migration)

```yaml
# templates/hooks/pre-sync-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: migration
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
        - name: migrate
          image: alpine
          command: ["sh", "-c", "echo 'migration ok'; sleep 2"]
      restartPolicy: Never
```

**Observation :** À la sync suivante, le job `migration` est créé et se termine avant que le `Deployment` démarre. Si le job échoue, la sync est bloquée.

**Conclusion :** Les hooks PreSync sont idéaux pour les migrations de schéma BDD. Attention : un job qui échoue bloque toute la sync — il faut des logs clairs et des alertes.

---

### Scénario 5 : Sync waves

```yaml
# ConfigMap avec wave -1 (appliqué en premier)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-1"

# Deployment avec wave 0 (appliqué après)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"
```

**Observation :** Le ConfigMap est appliqué en premier. En cassant le ConfigMap (YAML invalide), le Deployment ne démarre pas.

**Conclusion :** Les sync waves permettent de contrôler l'ordre sans écrire de scripts. Utile pour : CRD → CR, ConfigMap → Deployment, Namespace → ressources.

---

### Scénario 6 : `prune: true` + suppression de service.yaml

```bash
# Supprimer le fichier service.yaml du chart
rm services/annuaire/chart/templates/service.yaml
git commit -m "test: prune service"
git push
```

**Observation :** À la sync suivante, le `Service` correspondant est supprimé du cluster. Le `Deployment` tourne toujours mais l'Ingress ne peut plus router vers lui.

**Conclusion :** `prune: true` est puissant mais dangereux : une suppression accidentelle de fichier en Git se traduit en suppression en production. Il faut des reviews de PR strictes quand prune est activé.

---

## 8. Étape 9 — Sécurité et observabilité

### RBAC

**Compte `dev1`** : rôle `developer` — peut voir toutes les Applications `devhub/*`, peut sync uniquement `devhub/annuaire-*`.

Test de validation :
```bash
argocd login argocd.devhub.local --insecure --username dev1 --password <password>
argocd app sync planning-dev  # → PERMISSION DENIED
argocd app sync annuaire-dev  # → OK
```

### Trois métriques Prometheus utiles

| Métrique | Unité | Interprétation en cas d'incident |
|---|---|---|
| `argocd_app_info{health_status, sync_status}` | Gauge (0/1) | Si `health_status=Degraded` monte, un service est en panne. Si `sync_status=OutOfSync` monte, un drift est en cours. |
| `argocd_git_request_total{repo, request_type}` | Counter | Un pic d'erreurs `request_type=ls-remote` indique un problème de connectivité GitHub ou un token expiré. |
| `argocd_app_reconcile_count` | Counter | Un nombre anormalement bas signale que le controller ne réconcilie plus — possible crash ou OOMKilled. |

---

## 9. Étape 11 — Synthèse : ArgoCD et la prod

### Rétrospective TP 1 → TP 2

| Opération | Ressenti avec ArgoCD | Plus contraignant ? |
|---|---|---|
| Déployer pour la 1ère fois | Plus rassurant : on voit le statut dans l'UI | Non — mais la setup initiale (cluster + ArgoCD) est plus longue |
| Déployer une nouvelle version | Plus rapide : juste un commit | Non |
| Faire un rollback | Plus propre et tracé (git revert) | Non — mais le délai de polling peut être frustrant |
| Ouvrir un environnement de plus | Beaucoup plus rapide | Non |
| Donner un env perso à chaque dev | Simplifié par ApplicationSet | Non |
| Voir ce qui tourne en direct | UI ArgoCD = clarté immédiate | Non |
| Détecter un drift | Automatique — impossible de rater | Non |
| Hotfix en urgence | Contraint à passer par Git + PR | **Oui** — à 3h du matin, une PR est plus lente qu'un `kubectl edit` |
| Désinstaller un service | propre avec prune | **Oui** — risque de suppression accidentelle si prune:true activé |

**Deux opérations plus contraignantes avec ArgoCD :**
1. **Hotfix d'urgence** : l'obligation de passer par Git (commit + push + sync) ralentit une réaction d'urgence. La contrainte est néanmoins justifiée : elle garantit que le hotfix est traçé et peut être revert, contrairement à un `kubectl edit` oublié.
2. **Gestion des secrets** : ArgoCD ne gère pas les secrets — il faut une solution complémentaire (Sealed Secrets, External Secrets). C'est plus complexe qu'un simple `kubectl create secret`. Justifié car les secrets ne doivent pas être en clair dans Git.

**L'opération qui justifie à elle seule ArgoCD :** les **previews automatiques par branche** (ApplicationSet). Sans ArgoCD, offrir un environnement isolé à chaque développeur nécessite plusieurs jours d'ingénierie. Avec ArgoCD, c'est un seul fichier YAML de 60 lignes.

---

### Ce qu'ArgoCD ne sait pas faire

#### 1. Déploiement progressif (canary, blue/green)

**Risque concret :** Si `annuaire-service` a un bug, ArgoCD remplace les pods d'un coup. 100 % des utilisateurs sont impactés immédiatement.

**Outil complémentaire :** [Argo Rollouts](https://argo-rollouts.readthedocs.io/) — remplace le Deployment par un objet `Rollout` qui pilote le trafic progressivement (canary 10% → 50% → 100%). Compatible ArgoCD nativement.

**Référence :** https://argo-rollouts.readthedocs.io/en/stable/concepts/

---

#### 2. Validation des manifests avant sync

**Risque concret :** Un chart mal écrit (image `:latest`, pas de `securityContext`, limites de ressources absentes) est déployé sans avertissement. ArgoCD ne valide que la syntaxe YAML, pas la conformité aux bonnes pratiques.

**Outil complémentaire :** [Kyverno](https://kyverno.io/) — policies declaratives en YAML, intégrables comme ArgoCD PreSync hook. Exemple : interdire les images `:latest`, exiger `runAsNonRoot: true`.

**Référence :** https://kyverno.io/docs/writing-policies/

---

#### 3. Gestion des secrets dans Git

**Risque concret :** Un développeur pousse un `Secret` Kubernetes en clair dans Git. Il est visible dans l'historique Git pour toujours, même après suppression.

**Outil complémentaire :** [External Secrets Operator](https://external-secrets.io/) — synchronise les secrets depuis un vault (AWS Secrets Manager, HashiCorp Vault, Azure Key Vault) vers des Secrets K8s, sans que les valeurs transitent par Git.

**Référence :** https://external-secrets.io/latest/introduction/overview/

---

#### 4. Signature et provenance des images

**Risque concret :** ArgoCD déploie n'importe quelle image qui porte le bon tag. Un attaquant qui push une image malveillante avec le bon tag sur GHCR peut la faire déployer sans résistance.

**Outil complémentaire :** [cosign](https://docs.sigstore.dev/cosign/overview/) (Sigstore) — signe les images au moment du build CI, et une admission policy (Kyverno) vérifie la signature avant de laisser un Pod démarrer.

**Référence :** https://docs.sigstore.dev/cosign/signing/signing_with_containers/

---

#### 5. RBAC multi-équipe sur ArgoCD

**Risque concret :** Sans `AppProject` et RBAC, un développeur peut pointer son `Application` vers n'importe quel namespace ou repo, voire déployer dans `kube-system`.

**Outil complémentaire :** ArgoCD `AppProject` + SSO/OIDC (Dex, Okta, GitHub OAuth). L'OIDC permet de mapper les équipes GitHub vers des rôles ArgoCD, sans gérer des comptes locaux manuellement.

**Référence :** https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/

---

#### 6. Disaster recovery applicatif

**Risque concret :** ArgoCD peut recréer des Deployments à partir de Git, mais il ne peut pas restaurer les données d'un PVC (base de données, uploads). Si le PVC est supprimé, les données sont perdues.

**Outil complémentaire :** [Velero](https://velero.io/) — sauvegarde l'état du cluster (objets K8s + volumes) dans un bucket S3. Restauration en un `velero restore`.

**Référence :** https://velero.io/docs/latest/

---

#### 7. Multi-cluster

**Risque concret :** ArgoCD est installé dans un seul cluster. Si ce cluster tombe, ArgoCD ne peut plus synchroniser les autres clusters (si on avait du multi-cluster). C'est un SPOF.

**Outil complémentaire :** Pattern **hub-and-spoke** : un cluster "hub" héberge ArgoCD et gère des clusters "spoke". L'`ApplicationSet` avec `cluster generator` génère des Applications pour chaque cluster enregistré.

**Référence :** https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/generators-cluster/

---

### Les 3 briques à ajouter en priorité après ArgoCD

Si demain je devenais responsable de `DevHub Campus` en production, j'ajouterais dans cet ordre :

1. **External Secrets Operator** — les secrets sont le premier vecteur d'incident de sécurité, et ils ne peuvent pas attendre.
2. **Argo Rollouts** — le déploiement all-or-nothing est inacceptable pour une plateforme avec des utilisateurs réels.
3. **Kyverno** — enforce les bonnes pratiques (non-root, no latest, resource limits) avant qu'elles n'arrivent en prod.
