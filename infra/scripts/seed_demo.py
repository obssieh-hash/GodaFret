#!/usr/bin/env python3
"""Crée un jeu de données de démonstration dans Fineract (+ Keycloak).

- devise EUR, moyens de paiement, produits épargne et prêt ;
- rôle « Client mobile » (permissions minimales de l'application) ;
- un client « Camille Martin » (External Id = identifiant de connexion) avec
  compte courant, livret et un prêt décaissé ;
- un second client « Lucas Bernard » (bénéficiaire de transferts) ;
- l'utilisateur Fineract correspondant et, si --keycloak-url est fourni,
  l'utilisateur Keycloak (MFA TOTP exigée à la première connexion web).

Exemple (sur le serveur, ports internes via « docker compose port ») :
  python3 seed_demo.py --fineract http://localhost:8080/fineract-provider/api/v1 \
      --admin-user mifos --admin-password password \
      --keycloak-url http://localhost:8081 --keycloak-admin admin --keycloak-password '...' \
      --username camille --password 'MotDePasse-2026'

Uniquement les bibliothèques standard de Python.
"""
from __future__ import annotations

import argparse
import base64
import datetime as dt
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

# Permissions Fineract nécessaires à l'application mobile.
MOBILE_PERMISSIONS = [
    "READ_CLIENT",
    "READ_SAVINGSACCOUNT",
    "READ_LOAN",
    "READ_LOANPRODUCT",
    "READ_PAYMENTTYPE",
    "READ_ACCOUNTTRANSFER",
    "DEPOSIT_SAVINGSACCOUNT",
    "WITHDRAWAL_SAVINGSACCOUNT",
    "CREATE_ACCOUNTTRANSFER",
    "CREATE_LOAN",
    "REPAYMENT_LOAN",
    "CREATE_LOANNOTE",
]

FMT = {"locale": "en", "dateFormat": "yyyy-MM-dd"}


class Api:
    def __init__(self, base: str, user: str, password: str, tenant: str):
        self.base = base.rstrip("/")
        token = base64.b64encode(f"{user}:{password}".encode()).decode()
        self.headers = {
            "Authorization": f"Basic {token}",
            "Fineract-Platform-TenantId": tenant,
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

    def call(self, method: str, path: str, body=None, query=None):
        url = f"{self.base}{path}"
        if query:
            url += "?" + urllib.parse.urlencode(query)
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method, headers=self.headers)
        try:
            with urllib.request.urlopen(req, timeout=120) as res:
                raw = res.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")
            raise SystemExit(f"{method} {path} -> {e.code}\n{detail}") from None

    def get(self, path, **q):
        return self.call("GET", path, query=q or None)

    def post(self, path, body, **q):
        return self.call("POST", path, body, q or None)

    def put(self, path, body):
        return self.call("PUT", path, body)


def random_fineract_password() -> str:
    """Mot de passe conforme à la politique Fineract (12-50 caractères, majuscule,
    minuscule, chiffre, caractère spécial, sans espace ni caractère répété)."""
    import secrets
    import string
    alphabet = string.ascii_letters + string.digits
    out = ["A", "b", "7", "#"]
    while len(out) < 28:
        c = secrets.choice(alphabet)
        if c != out[-1]:
            out.append(c)
    return "".join(out)


def day(offset: int) -> str:
    return (dt.date.today() + dt.timedelta(days=offset)).isoformat()


def find(items, **crit):
    for it in items:
        if all(it.get(k) == v for k, v in crit.items()):
            return it
    return None


def ensure_payment_types(api: Api):
    existing = api.get("/paymenttypes")
    for pos, (name, cash) in enumerate([("Espèces en agence", True), ("Mobile money", False)], start=1):
        if not find(existing, name=name):
            api.post("/paymenttypes", {"name": name, "description": name, "isCashPayment": cash, "position": pos})


def ensure_savings_product(api: Api, name: str, short: str, rate: float) -> int:
    found = find(api.get("/savingsproducts"), name=name)
    if found:
        return found["id"]
    return api.post("/savingsproducts", {
        "locale": "en",
        "name": name,
        "shortName": short,
        "currencyCode": "EUR",
        "digitsAfterDecimal": 2,
        "inMultiplesOf": 0,
        "nominalAnnualInterestRate": rate,
        "interestCompoundingPeriodType": 1,
        "interestPostingPeriodType": 4,
        "interestCalculationType": 1,
        "interestCalculationDaysInYearType": 365,
        "accountingRule": 1,
    })["resourceId"]


def ensure_loan_product(api: Api, name: str, short: str, rate: float, pmin, pmax, pdef, nmin, nmax, ndef) -> int:
    found = find(api.get("/loanproducts"), name=name)
    if found:
        return found["id"]
    return api.post("/loanproducts", {
        "locale": "en",
        "name": name,
        "shortName": short,
        "description": f"{name} — produit de démonstration",
        "currencyCode": "EUR",
        "digitsAfterDecimal": 2,
        "inMultiplesOf": 0,
        "principal": pdef,
        "minPrincipal": pmin,
        "maxPrincipal": pmax,
        "numberOfRepayments": ndef,
        "minNumberOfRepayments": nmin,
        "maxNumberOfRepayments": nmax,
        "repaymentEvery": 1,
        "repaymentFrequencyType": 2,
        "interestRatePerPeriod": rate,
        "interestRateFrequencyType": 2,
        "amortizationType": 1,
        "interestType": 0,
        "interestCalculationPeriodType": 1,
        "transactionProcessingStrategyCode": "mifos-standard-strategy",
        "daysInYearType": 1,
        "daysInMonthType": 1,
        "isInterestRecalculationEnabled": False,
        "accountingRule": 1,
    })["resourceId"]


def ensure_client(api: Api, external_id: str, first: str, last: str, mobile: str, email: str) -> int:
    page = api.get("/clients", externalId=external_id)
    if page.get("pageItems"):
        return page["pageItems"][0]["id"]
    return api.post("/clients", {
        **FMT,
        "officeId": 1,
        "legalFormId": 1,
        "firstname": first,
        "lastname": last,
        "externalId": external_id,
        "mobileNo": mobile,
        "emailAddress": email,
        "active": True,
        "activationDate": day(-120),
        "submittedOnDate": day(-120),
    })["clientId"]


def ensure_savings(api: Api, client_id: int, product_id: int, opening: float) -> int:
    accounts = api.get(f"/clients/{client_id}/accounts").get("savingsAccounts", [])
    found = find(accounts, productId=product_id)
    if found:
        return found["id"]
    sid = api.post("/savingsaccounts", {**FMT, "clientId": client_id, "productId": product_id, "submittedOnDate": day(-110)})["savingsId"]
    api.post(f"/savingsaccounts/{sid}", {**FMT, "approvedOnDate": day(-110)}, command="approve")
    api.post(f"/savingsaccounts/{sid}", {**FMT, "activatedOnDate": day(-110)}, command="activate")
    if opening:
        api.post(f"/savingsaccounts/{sid}/transactions", {**FMT, "transactionDate": day(-100), "transactionAmount": opening, "paymentTypeId": api.get("/paymenttypes")[0]["id"]}, command="deposit")
    return sid


def ensure_loan(api: Api, client_id: int, product_id: int) -> int:
    loans = api.get(f"/clients/{client_id}/accounts").get("loanAccounts", [])
    found = find(loans, productId=product_id)
    if found:
        return found["id"]
    t = api.get("/loans/template", templateType="individual", clientId=client_id, productId=product_id)
    lid = api.post("/loans", {
        **FMT,
        "loanType": "individual",
        "clientId": client_id,
        "productId": product_id,
        "principal": 6000,
        "numberOfRepayments": 24,
        "repaymentEvery": 1,
        "repaymentFrequencyType": t["repaymentFrequencyType"]["id"],
        "loanTermFrequency": 24,
        "loanTermFrequencyType": t["repaymentFrequencyType"]["id"],
        "interestRatePerPeriod": t["interestRatePerPeriod"],
        "amortizationType": t["amortizationType"]["id"],
        "interestType": t["interestType"]["id"],
        "interestCalculationPeriodType": t["interestCalculationPeriodType"]["id"],
        "transactionProcessingStrategyCode": t["transactionProcessingStrategyCode"],
        "expectedDisbursementDate": day(-95),
        "submittedOnDate": day(-95),
    })["loanId"]
    api.post(f"/loans/{lid}", {**FMT, "approvedOnDate": day(-95)}, command="approve")
    api.post(f"/loans/{lid}", {**FMT, "actualDisbursementDate": day(-95), "transactionAmount": 6000}, command="disburse")
    return lid


def ensure_role(api: Api) -> int:
    role = find(api.get("/roles"), name="Client mobile")
    rid = role["id"] if role else api.post("/roles", {"name": "Client mobile", "description": "Clients de l'application mobile"})["resourceId"]
    api.put(f"/roles/{rid}/permissions", {"permissions": {p: True for p in MOBILE_PERMISSIONS}})
    return rid


def ensure_app_user(api: Api, username: str, password: str, role_id: int, first: str, last: str, email: str):
    if find(api.get("/users"), username=username):
        return
    api.post("/users", {
        "username": username,
        "firstname": first,
        "lastname": last,
        "email": email,
        "officeId": 1,
        "roles": [role_id],
        "sendPasswordToEmail": False,
        "passwordNeverExpires": True,
        # Mot de passe Fineract aléatoire : la connexion se fait via Keycloak.
        "password": password,
        "repeatPassword": password,
    })


def keycloak_user(url: str, admin: str, admin_password: str, username: str, password: str,
                  first: str, last: str, email: str, client_id: int, require_otp: bool):
    def req(method, path, body=None, token=None, form=None):
        headers = {"Accept": "application/json"}
        data = None
        if form is not None:
            data = urllib.parse.urlencode(form).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        elif body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        if token:
            headers["Authorization"] = f"Bearer {token}"
        r = urllib.request.Request(url.rstrip("/") + path, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(r, timeout=60) as res:
                raw = res.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            raise SystemExit(f"Keycloak {method} {path} -> {e.code} {e.read().decode(errors='replace')}") from None

    token = req("POST", "/realms/master/protocol/openid-connect/token", form={
        "grant_type": "password", "client_id": "admin-cli", "username": admin, "password": admin_password,
    })["access_token"]

    # Autorise l'attribut fineract_client_id (profil utilisateur Keycloak 24+).
    profile = req("GET", "/admin/realms/godafret/users/profile", token=token)
    if profile.get("unmanagedAttributePolicy") != "ADMIN_EDIT":
        profile["unmanagedAttributePolicy"] = "ADMIN_EDIT"
        req("PUT", "/admin/realms/godafret/users/profile", profile, token=token)

    existing = req("GET", f"/admin/realms/godafret/users?exact=true&username={urllib.parse.quote(username)}", token=token)
    body = {
        "username": username,
        "firstName": first,
        "lastName": last,
        "email": email,
        "emailVerified": True,
        "enabled": True,
        "attributes": {"fineract_client_id": [str(client_id)]},
        "requiredActions": ["CONFIGURE_TOTP"] if require_otp else [],
    }
    if not existing:
        req("POST", "/admin/realms/godafret/users", body, token=token)
        existing = req("GET", f"/admin/realms/godafret/users?exact=true&username={urllib.parse.quote(username)}", token=token)
    uid = existing[0]["id"]
    # Réapplique le profil : Keycloak ajoute les actions par défaut à la création.
    req("PUT", f"/admin/realms/godafret/users/{uid}", body, token=token)
    try:
        req("PUT", f"/admin/realms/godafret/users/{uid}/reset-password",
            {"type": "password", "value": password, "temporary": False}, token=token)
    except SystemExit as e:
        # Relance du script avec le même mot de passe : historique des mots de passe.
        if "PasswordHistory" not in str(e):
            raise


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--fineract", default="http://localhost:8080/fineract-provider/api/v1")
    p.add_argument("--tenant", default="default")
    p.add_argument("--admin-user", default="mifos")
    p.add_argument("--admin-password", default="password")
    p.add_argument("--username", default="camille")
    p.add_argument("--password", required=True, help="mot de passe Keycloak du client de démo")
    p.add_argument("--keycloak-url")
    p.add_argument("--keycloak-admin", default="admin")
    p.add_argument("--keycloak-password")
    p.add_argument("--no-otp", action="store_true", help="ne pas exiger la configuration TOTP (tests uniquement)")
    a = p.parse_args()

    api = Api(a.fineract, a.admin_user, a.admin_password, a.tenant)
    api.put("/currencies", {"currencies": ["EUR"]})
    ensure_payment_types(api)
    current = ensure_savings_product(api, "Compte courant", "CC", 0)
    livret = ensure_savings_product(api, "Livret Épargne+", "LIV", 2)
    perso = ensure_loan_product(api, "Prêt personnel", "PP", 0.5, 1000, 30000, 5000, 6, 72, 24)
    ensure_loan_product(api, "Microcrédit pro", "MC", 0.9, 200, 5000, 1500, 3, 24, 12)

    camille = ensure_client(api, a.username, "Camille", "Martin", "+33612345678", "camille.martin@example.com")
    cc = ensure_savings(api, camille, current, 2500)
    ensure_savings(api, camille, livret, 6000)
    ensure_loan(api, camille, perso)
    lucas = ensure_client(api, "lucas", "Lucas", "Bernard", "+33698765432", "lucas.bernard@example.com")
    lucas_cc = ensure_savings(api, lucas, current, 100)

    role = ensure_role(api)
    ensure_app_user(api, a.username, random_fineract_password(), role, "Camille", "Martin", "camille.martin@example.com")

    if a.keycloak_url:
        if not a.keycloak_password:
            sys.exit("--keycloak-password est requis avec --keycloak-url")
        keycloak_user(a.keycloak_url, a.keycloak_admin, a.keycloak_password, a.username, a.password,
                      "Camille", "Martin", "camille.martin@example.com", camille, not a.no_otp)

    lucas_no = api.get(f"/savingsaccounts/{lucas_cc}")["accountNo"]
    cc_no = api.get(f"/savingsaccounts/{cc}")["accountNo"]
    print(json.dumps({"clientId": camille, "compteCourant": cc_no, "beneficiaireLucas": lucas_no}, indent=2))


if __name__ == "__main__":
    main()
