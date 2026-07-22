"""
Taobao/Tmall product parser with login support.
Usage: python taobao_parser.py <url> [sms_code]
All strings use unicode escapes - no raw Chinese in source.
"""
import asyncio, sys, json, re, io
from pathlib import Path
from datetime import datetime
from playwright.async_api import async_playwright

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')

WORKSPACE = Path(__file__).parent
COOKIE_FILE = WORKSPACE / "data/.taobao_cookies.json"
EXCEL_FILE = WORKSPACE / "\u91c7\u8d2d\u6e05\u5355.xlsx"

def load_creds():
    env_file = WORKSPACE / "data/.taobao.env"
    if not env_file.exists(): return None, None
    creds = {}
    for line in env_file.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            creds[k.strip()] = v.strip()
    return creds.get("TAOBAO_USERNAME"), creds.get("TAOBAO_PASSWORD")

async def extract_current_price(page) -> str:
    """Read the current displayed price from the page."""
    # Try specific price elements first (more accurate than body text)
    price_selectors = [
        '.tm-price .tm-count',
        '#J_StrPrice .tb-rmb-num',
        '#J_PromoPriceNum',
        '.tb-rmb-num',
        '.tm-count',
        'em.tb-rmb-num',
    ]
    for sel in price_selectors:
        try:
            el = await page.query_selector(sel)
            if el:
                text = (await el.inner_text()).strip()
                if text:
                    return "¥" + text
        except Exception:
            continue

    # Fallback: scan body text for prices
    try:
        body = (await page.inner_text("body"))[:10000]
        prices = re.findall(r'[\xa5￥]\s*([\d,.]+)', body)
        for p in prices:
            val = float(p.replace(",", ""))
            if 0 < val < 500000:
                return "¥" + p
    except Exception:
        pass
    return ""


async def get_selected_sku(page) -> str:
    """Find the currently selected SKU variant name on the page.
    Returns the SKU name if one is already selected, empty string otherwise."""
    selected_selectors = [
        ".tb-selected span",
        ".tb-selected a",
        ".tb-selected",
        ".SKU--selected",
        "li.active span",
        "li.selected span",
        "li.tb-active",
        '[aria-selected="true"]',
        ".sku-item.selected",
        ".sku-item.active",
    ]
    for sel in selected_selectors:
        try:
            el = await page.query_selector(sel)
            if el:
                name = (await el.inner_text()).strip()[:60]
                if name:
                    return name
        except Exception:
            continue
    return ""


async def detect_sku_prices(page) -> list:
    """Click through SKU variant options and capture price for each.
    Returns list of {sku_name, price} dicts."""
    results = []
    clicked_texts = set()

    # Find SKU property groups
    sku_groups = await page.query_selector_all(
        ".J_TSaleProp, .tb-prop, .sku-line, ul[data-property], "
        ".tb-sku, .tb-skin, .J_SKU"
    )

    # Collect all clickable SKU items from the first valid group
    sku_items = []
    for group in sku_groups:
        items = await group.query_selector_all(
            "li:not(.tb-out-of-stock):not(.disabled):not(.tb-disable), "
            "a:not(.tb-out-of-stock), "
            ".sku-item:not(.disable), "
            "span[data-value]"
        )
        if items and len(items) > 1:
            sku_items = items
            break

    # Fallback: look for any SKU-like clickable elements
    if not sku_items:
        sku_items = await page.query_selector_all(
            ".J_TSaleProp li:not(.tb-out-of-stock), "
            ".tb-prop li:not(.tb-out-of-stock), "
            "li[data-pv], li[data-sku-id], "
            "a[data-sku-id]"
        )

    for item in sku_items:
        try:
            name = (await item.inner_text()).strip()[:60]
            if not name or name in clicked_texts:
                continue
            clicked_texts.add(name)

            # Check for disabled/out-of-stock
            classes = (await item.get_attribute("class")) or ""
            if any(x in classes for x in ["disabled", "out-of-stock", "tb-out-of-stock"]):
                continue

            # Scroll into view and click
            await item.scroll_into_view_if_needed()
            try:
                await item.click(timeout=5000)
            except Exception:
                # Some items are wrapped - click the inner element
                inner = await item.query_selector("a, span, div")
                if inner:
                    await inner.click(timeout=5000)
                else:
                    continue

            # Wait for price to update via JS
            await page.wait_for_timeout(2500)

            price = await extract_current_price(page)
            if price:
                results.append({"sku": name, "price": price})
        except Exception:
            continue

    return results


async def do_login(page, username, password, sms_code=None):
    print("[login] Loading...", flush=True)
    await page.goto("https://login.taobao.com/", wait_until="domcontentloaded", timeout=30000)
    await page.wait_for_timeout(3000)
    if "login" not in page.url.lower(): return True
    for sel in ['text=\u5bc6\u7801\u767b\u5f55', 'a:has-text("\u5bc6\u7801\u767b\u5f55")']:
        tab = await page.query_selector(sel)
        if tab: await tab.click(); await page.wait_for_timeout(2000); break
    try:
        cb = await page.query_selector('#fm-agreement-checkbox')
        if cb and not await cb.is_checked(): await cb.check(); await page.wait_for_timeout(500)
    except: pass
    for sel in ['#fm-login-id', 'input[placeholder*="\u624b\u673a"]']:
        el = await page.query_selector(sel)
        if el: await el.click(); await el.fill(""); await el.fill(username); await page.wait_for_timeout(500); break
    for sel in ['#fm-login-password', 'input[type="password"]']:
        el = await page.query_selector(sel)
        if el: await el.click(); await el.fill(""); await el.fill(password); await page.wait_for_timeout(500); break
    for sel in ['#fm-login-submit', 'button[type="submit"]', '.fm-button']:
        btn = await page.query_selector(sel)
        if btn: await btn.click(); break
    else: await page.keyboard.press("Enter")
    try: await page.wait_for_url(lambda u: "login" not in u.lower(), timeout=15000); return True
    except: pass
    await page.wait_for_timeout(3000)
    if "login" not in page.url.lower(): return True
    for s in ['#fm-smscode', 'input[placeholder*="\u9a8c\u8bc1\u7801"]']:
        sms = await page.query_selector(s)
        if sms:
            if not sms_code: return {"need_sms": True}
            await sms.click(); await sms.fill(sms_code); await page.wait_for_timeout(500)
            for b in ['#fm-submit', '.sms-btn', '.fm-button']:
                btn = await page.query_selector(b)
                if btn: await btn.click(); break
            await page.wait_for_timeout(5000)
            try: await page.wait_for_url(lambda u: "login" not in u.lower(), timeout=10000)
            except: pass
            if "login" not in page.url.lower(): return True
            break
    return "login" not in page.url.lower()

async def parse_product(page, url: str) -> dict:
    print("[parse] Loading product page...", flush=True)
    await page.goto(url, wait_until="load", timeout=60000)
    await page.wait_for_timeout(20000)
    final_url = page.url
    if "login" in final_url.lower(): return {"need_relogin": True}
    
    body_text = (await page.inner_text("body"))[:10000]
    page_title = (await page.title()).split("-")[0].strip()
    
    # Title
    title = page_title
    
    # Price (match yen symbol variations)
    prices = re.findall(r'[\xa5\uffe5]\s*([\d,.]+)', body_text)
    price = ""
    for p in prices:
        val = float(p.replace(",",""))
        if 0 < val < 500000: price = "\u00a5" + p; break
    
    # Shop: try patterns in body text first, then JS fallback
    shop = ""
    # Match common Chinese shop name patterns
    for pat in [r'([^\n]{2,15}\u5b98\u65b9\u65d7\u8230\u5e97)',
                r'([^\n]{2,10}\u65d7\u8230\u5e97)',
                r'([^\n]{2,10}\u4e13\u5356\u5e97)']:
        m = re.search(pat, body_text)
        if m: shop = m.group(1); break
    if not shop:
        m = re.search(r'([^\n]{2,15})\n5\.0\n', body_text)
        if m: shop = m.group(1).strip()
    if not shop:
        m = re.search(r'([^\n]{2,12}\u5e97)\s*>', body_text)
        if m: shop = m.group(1)
    if not shop:
        shop = await page.evaluate("""() => {
            const els = document.querySelectorAll('a[href*="shop"]');
            for (const el of els) {
                const t = el.textContent.trim();
                const lines = t.split('\\n');
                for (let i = 0; i < lines.length - 1; i++)
                    if (/^\\d+\\.\\d+$/.test(lines[i+1])) return lines[i].trim();
            }
            return '';
        }""")
    
    # SKU from reviews or body text
    sku_text = ""
    review_m = re.findall(r'\u5df2\u8d2d[\uff1a:]?([^\n]{5,60})', body_text)
    if review_m:
        sku_clean = re.sub(r'\[[^\]]*\]', '', review_m[0]).strip()
        sku_text = sku_clean
    if not sku_text:
        for pat in [r'\u989c\u8272\u5206\u7c7b[\uff1a:]?\s*([^\n]+)',
                     r'\u5df2\u9009[\uff1a:]?\s*([^\n]+)',
                     r'\u6b3e\u5f0f[\uff1a:]?\s*([^\n]+)',
                     r'\u5c3a\u7801[\uff1a:]?\s*([^\n]+)']:
            m = re.search(pat, body_text)
            if m: sku_text = m.group(1).strip()[:30]; break
    
    item_id = ""
    id_m = re.search(r'(?:id=|item/|itemId=)(\d+)', final_url)
    if id_m: item_id = id_m.group(1)

    items = []

    # First: check if URL already targets a specific SKU (user selected variant before sharing)
    sku_id_from_url = ""
    sku_id_m = re.search(r'[?&]skuId=(\d+)', final_url)
    if sku_id_m:
        sku_id_from_url = sku_id_m.group(1)
        print(f"[parse] SKU detected in URL: {sku_id_from_url}", flush=True)

    # Try to read the already-selected SKU on the current page
    selected_sku = await get_selected_sku(page)
    if selected_sku:
        current_price = await extract_current_price(page)
        if current_price:
            items.append({"sku": selected_sku, "price": current_price})
            print(f"[parse] Pre-selected SKU: [{selected_sku}] {current_price}", flush=True)

    # If no pre-selected SKU found, click through all variants
    if not items:
        print("[parse] No pre-selected SKU, detecting all variants...", flush=True)
        sku_prices = await detect_sku_prices(page)
        if sku_prices:
            for sp in sku_prices:
                items.append({"sku": sp["sku"], "price": sp["price"]})
            print(f"[parse] Found {len(items)} SKU variants", flush=True)
        else:
            # Last resort: use default price with best-effort SKU name
            items.append({"sku": sku_text, "price": price})
            print("[parse] No SKU variants detected, using default price", flush=True)

    return {"ok": True, "title": title, "items": items,
            "shop": shop, "item_id": item_id, "final_url": final_url, "short_url": url}

def append_to_excel(products: list):
    from openpyxl import Workbook, load_workbook
    from openpyxl.styles import Font, Alignment, PatternFill, Border, Side
    
    headers = ["\u65e5\u671f", "\u91c7\u8d2d\u7269\u54c1", "\u6570\u91cf",
               "\u6e20\u9053", "\u4ef7\u683c", "\u94fe\u63a5"]
    thin_border = Border(left=Side(style='thin'), right=Side(style='thin'),
                         top=Side(style='thin'), bottom=Side(style='thin'))
    data_font = Font(name="Microsoft YaHei", size=11)
    
    if EXCEL_FILE.exists():
        wb = load_workbook(EXCEL_FILE)
        ws = wb.active
    else:
        wb = Workbook()
        ws = wb.active
        ws.title = "\u91c7\u8d2d\u6e05\u5355"
        header_fill = PatternFill(start_color="4472C4", end_color="4472C4", fill_type="solid")
        header_font = Font(name="Microsoft YaHei", bold=True, color="FFFFFF", size=11)
        for col, h in enumerate(headers, 1):
            cell = ws.cell(row=1, column=col, value=h)
            cell.font = header_font; cell.fill = header_fill
            cell.alignment = Alignment(horizontal='center', vertical='center')
            cell.border = thin_border
        for i, w in enumerate([12, 45, 8, 10, 12, 45], 1):
            ws.column_dimensions[ws.cell(row=1, column=i).column_letter].width = w
    
    next_row = ws.max_row + 1
    today = datetime.now().strftime("%m-%d")
    
    for prod in products:
        link = prod.get("short_url", "")
        items = prod.get("items", [{"sku": prod.get("sku", ""), "price": prod.get("price", "")}])

        for item in items:
            item_name = item.get("sku", "") or prod.get("title", "")

            ws.cell(row=next_row, column=1, value=today).font = data_font
            ws.cell(row=next_row, column=2, value=item_name).font = data_font
            ws.cell(row=next_row, column=3, value="1").font = data_font
            ws.cell(row=next_row, column=4, value=prod.get("channel", "Taobao")).font = data_font
            ws.cell(row=next_row, column=5, value=item.get("price", "")).font = data_font

            if link:
                cell = ws.cell(row=next_row, column=6, value="\u6253\u5f00\u94fe\u63a5")
                cell.hyperlink = link
                cell.font = Font(name="Microsoft YaHei", size=11, color="0563C1", underline="single")

            for col in range(1, 7):
                c = ws.cell(row=next_row, column=col)
                c.alignment = Alignment(horizontal='center' if col != 2 else 'left', vertical='center')
                c.border = thin_border
            next_row += 1
    
    wb.save(EXCEL_FILE)
    return EXCEL_FILE

async def main():
    if len(sys.argv) < 2:
        print(json.dumps({"ok":False,"error":"Usage: python taobao_parser.py <url> [sms_code]"}))
        return
    url = sys.argv[1]
    sms_code = sys.argv[2] if len(sys.argv) > 2 else None
    username, password = load_creds()
    
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True, args=["--disable-blink-features=AutomationControlled"])
        context = await browser.new_context(
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0.0.0 Safari/537.36",
            viewport={"width": 1366, "height": 768}, locale="zh-CN")
        if COOKIE_FILE.exists():
            try: await context.add_cookies(json.loads(COOKIE_FILE.read_text(encoding="utf-8")))
            except: pass
        page = await context.new_page()
        
        login_result = await do_login(page, username, password, sms_code)
        if isinstance(login_result, dict):
            print(json.dumps(login_result, ensure_ascii=False)); await browser.close(); return
        if not login_result:
            print(json.dumps({"ok":False,"error":"login_failed"}, ensure_ascii=False)); await browser.close(); return
        
        cookies = await context.cookies()
        COOKIE_FILE.write_text(json.dumps(cookies, ensure_ascii=False, indent=2))
        
        result = await parse_product(page, url)
        if result.get("need_relogin"):
            relogin = await do_login(page, username, password, sms_code)
            if isinstance(relogin, dict) or not relogin:
                print(json.dumps(relogin if isinstance(relogin,dict) else {"ok":False}, ensure_ascii=False))
                await browser.close(); return
            cookies = await context.cookies()
            COOKIE_FILE.write_text(json.dumps(cookies, ensure_ascii=False, indent=2))
            result = await parse_product(page, url)
        
        result["channel"] = "Taobao"

        items = result.get("items", [])
        if result.get("ok") and (result.get("title") or items):
            excel_path = append_to_excel([result])
            from openpyxl import load_workbook
            wb = load_workbook(EXCEL_FILE)
            ws = wb.active
            print(f"Added {len(items)} row(s) -> {EXCEL_FILE.name}", flush=True)
            for item in items:
                sku = item.get("sku", "") or "(default)"
                price = item.get("price", "?")
                print(f"  [{sku}] {price}", flush=True)
        else:
            print("ERROR: Failed to parse product.", flush=True)
        
        await browser.close()

if __name__ == "__main__":
    asyncio.run(main())
