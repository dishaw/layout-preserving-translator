/*
 * (c) Copyright Ascensio System SIA 2010
 *
 * This program is a free software product. You can redistribute it and/or
 * modify it under the terms of the GNU Affero General Public License (AGPL)
 * version 3 as published by the Free Software Foundation. In accordance with
 * Section 7(a) of the GNU AGPL its Section 15 shall be amended to the effect
 * that Ascensio System SIA expressly excludes the warranty of non-infringement
 * of any third-party rights.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without even the implied
 * warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR  PURPOSE. For
 * details, see the GNU AGPL at: http://www.gnu.org/licenses/agpl-3.0.html
 *
 * You can contact Ascensio System SIA at 20A-6 Ernesta Birznieka-Upish
 * street, Riga, Latvia, EU, LV-1050.
 *
 * The  interactive user interfaces in modified source and object code versions
 * of the Program must display Appropriate Legal Notices, as required under
 * Section 5 of the GNU AGPL version 3.
 *
 * Pursuant to Section 7(b) of the License you must retain the original Product
 * logo when distributing the program. Pursuant to Section 7(e) we decline to
 * grant you any rights under trademark law for use of our trademarks.
 *
 * All the Product's GUI elements, including illustrations and icon sets, as
 * well as technical writing content are licensed under the terms of the
 * Creative Commons Attribution-ShareAlike 4.0 International. See the License
 * terms at http://creativecommons.org/licenses/by-sa/4.0/legalcode
 *
 */
 
(function(window, undefined){
	var isInit = false;
	var ifr;
	const isIE = checkInternetExplorer();	//check IE
	var prevTxt;
	var txt;
	var paste_done  = true;
	var translated = '';
	var replaceWholeDocument = false;
	var selectionParagraphCount = 0;
	
	window.Asc.plugin.init = function(text)
	{
		if (isIE) {
			showMessage("This plugin doesn't work in Internet Explorer.");
			return;
		}
		if (window.Asc.plugin.info.editorType === 'word') {
			window.Asc.plugin.executeMethod("GetSelectedText", [{Numbering:false}], function(data) {
				prevTxt = txt;
				txt = (!data) ? "" : ProcessText(data);
				replaceWholeDocument = false;
				selectionParagraphCount = countTextParagraphs(txt);
				ExecPlugin();
			});
		} else {
			prevTxt = txt;
			txt = ProcessText(text);
			replaceWholeDocument = false;
			selectionParagraphCount = 0;
			ExecPlugin();
		}
	};

	function ExecPlugin() {
		if (!isInit) {
			document.getElementById("iframe_parent").innerHTML = "";

			ifr                = document.createElement("iframe");
			ifr.position	   = "fixed";
			ifr.name           = "google_name";
			ifr.id             = "google_id";
			ifr.src            = "./index_widget.html";//?text=" + encodeURIComponent(text);
			ifr.style.top      = "0px";
			ifr.style.left     = "0px";
			ifr.style.width    = "100%";
			ifr.style.height   = "100%";
			ifr.setAttribute("frameBorder", "0");
			document.getElementById("iframe_parent").appendChild(ifr);
			isInit = true;
			ifr.onload = function() {
				if (ifr.contentWindow.document.readyState == 'complete') {
					window.Asc.plugin.onThemeChanged(Asc.plugin.theme);
				}

				setTimeout(function() {
					let element = ifr.contentDocument ? ifr.contentDocument.getElementById("google_translate_element") : null;
					if (element) {
						element.textContent = txt;
					}
				}, 500);

				// 先创建 Copy / Insert 按钮（不依赖 Google 翻译）
				ifr.contentDocument.getElementById("google_translate_element").style.height = "fit-content";
				var btn = ifr.contentDocument.createElement("button");
				var btnReplace = ifr.contentDocument.createElement("button");
				var div = ifr.contentDocument.createElement("div");
				div.appendChild(btn);
				if (!window.Asc.plugin.info.isViewMode)
					div.appendChild(btnReplace);
				div.id = "div_btn";
				div.classList.add("skiptranslate");
				div.classList.add("div_btn");
				div.classList.add("hidden");
				btn.innerHTML = window.Asc.plugin.tr("Copy");
				btn.id = "btn_copy";
				btn.classList.add("btn-text-default");
				btnReplace.classList.add("btn-text-default");
				btnReplace.innerHTML = window.Asc.plugin.tr("Insert");
				btnReplace.id = "btn_replace";
				setTimeout(function() {
					ifr.contentDocument.getElementById("body").appendChild(div);
				}, 100);
				setTimeout(function() {
					btnReplace.onclick = function () {
						if (!paste_done) return;
						paste_done = false;
						var translatedTxt = ifr.contentDocument.getElementById("google_translate_element").outerText;
						replaceTextPreservingOriginalFormat(translatedTxt, { selectAll: replaceWholeDocument }, function() {
							paste_done = true;
						});
					};
				});

				var selectElement = ifr.contentDocument.getElementsByClassName('goog-te-combo')[0];
				if (!selectElement) {
					div.classList.remove("hidden");
					return;
				}
				selectElement.addEventListener('change', function(event) {
					if (txt || ifr.contentDocument.getElementById("google_translate_element").innerHTML) {
						ifr.contentWindow.postMessage("onchange_goog-te-combo", '*');
						ifr.contentDocument.getElementById("google_translate_element").style.opacity = 0;
					}
				});
				var select = ifr.contentDocument.createElement("select");
				select.id = "select_lang";
				select.classList.add("select-lang");
				select.classList.add("goog-te-combo");
				setTimeout(function() {
					ifr.contentDocument.getElementById(":0.targetLanguage").appendChild(select);
				}, 100);
				ifr.contentWindow.postMessage("update_scroll", '*');
				ifr.contentWindow.postMessage({type: 'translate', text: translated}, '*')
			}
		} else if(prevTxt != txt) {
			ifr.contentWindow.postMessage(txt, '*');
			ifr.contentDocument.getElementById("google_translate_element").style.opacity = 0;
		}
	};
	function extractSelectedText(value) {
		if (value == null) return "";
		if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
			return String(value);
		}
		if (Array.isArray(value)) {
			return value.map(extractSelectedText).filter(Boolean).join("\n");
		}
		if (typeof value === "object") {
			var keys = ["text", "Text", "value", "Value", "data", "Data", "result", "Result"];
			for (var i = 0; i < keys.length; i++) {
				if (value[keys[i]] != null) {
					var nested = extractSelectedText(value[keys[i]]);
					if (nested) return nested;
				}
			}
			var collected = [];
			for (var key in value) {
				if (!Object.prototype.hasOwnProperty.call(value, key)) continue;
				if (typeof value[key] === "string" && value[key]) collected.push(value[key]);
			}
			return collected.join("\n");
		}
		return "";
	}

	function ProcessText(sText) {
		sText = extractSelectedText(sText);
		return sText.replace(/	/gi, '\n').replace(/	/gi, '\n');
	};

	function countTextParagraphs(value) {
		var text = String(value || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n");
		if (!text) return 0;
		var parts = text.split(/\n/);
		while (parts.length > 1 && parts[parts.length - 1] === "") {
			parts.pop();
		}
		return Math.max(parts.length, 1);
	}

	// 解析 Google 翻译结果，还原段落数组（提取自 btnReplace.onclick 逻辑）
	function parseTranslatedParagraphs(translatedTxt) {
		var allParasTxt = (translatedTxt || "").split(/\n/);
		var allParsedParas = [];
		for (var nStr = 0; nStr < allParasTxt.length; nStr++) {
			if (allParasTxt[nStr].search(/	/) === 0) {
				allParsedParas.push("");
				allParasTxt[nStr] = allParasTxt[nStr].replace(/	/, "");
			}
			var sSplited = allParasTxt[nStr].split(/	/);
			sSplited.forEach(function(item, i, sSplited) {
				allParsedParas.push(item);
			});
		}
		return allParsedParas;
	}

	function fitParagraphsToSelection(paragraphs, selectedCount) {
		var arr = paragraphs || [];
		var count = selectedCount || 0;
		if (count <= 0 || arr.length === count) return arr;
		if (arr.length < count) {
			while (arr.length < count) arr.push("");
			return arr;
		}
		if (count === 1) return [arr.join("\n")];
		var fitted = arr.slice(0, count - 1);
		fitted.push(arr.slice(count - 1).join("\n"));
		return fitted;
	}

	// ReplaceTextSmart keeps the selected text run/paragraph formatting when possible.
	function replaceTextPreservingOriginalFormat(translatedTxt, options, callback) {
		var done = false;
		function finish() {
			if (done) return;
			done = true;
			if (callback) callback();
		}
		function pastePlainText() {
			window.Asc.plugin.executeMethod("PasteText", [translatedTxt || ""], finish);
		}
		function splitCellTranslations(text) {
			var normalized = String(text || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n");
			var parts = normalized.split(/\t|\n/);
			while (parts.length > 1 && parts[parts.length - 1] === "") {
				parts.pop();
			}
			return parts;
		}
		function setCellValueOnly() {
			Asc.scope.translatorCellValue = translatedTxt || "";
			Asc.scope.translatorCellValues = splitCellTranslations(translatedTxt);
			window.Asc.plugin.callCommand(function() {
				function getRangeAddress(range) {
					if (!range) return "";
					try {
						if (typeof range.GetAddress === "function") return range.GetAddress() || "";
					} catch (e) {}
					try {
						if (typeof range.Address !== "undefined") return range.Address || "";
					} catch (e) {}
					return "";
				}
				function getFirstCellAddress(address) {
					var addr = (address || "").toString();
					if (!addr) return "";
					var bangIndex = addr.lastIndexOf("!");
					if (bangIndex >= 0) addr = addr.substring(bangIndex + 1);
					addr = addr.split(",")[0].split(":")[0].replace(/\$/g, "").replace(/'/g, "");
					return addr;
				}
				function getCellAddress(cell) {
					if (!cell) return "";
					try {
						if (typeof cell.GetAddress === "function") return cell.GetAddress() || "";
					} catch (e) {}
					try {
						if (typeof cell.Address !== "undefined") return cell.Address || "";
					} catch (e) {}
					return "";
				}
				function setValue(cell, value) {
					try {
						if (cell && typeof cell.SetValue === "function") {
							cell.SetValue(value);
							return true;
						}
					} catch (e) {}
					try {
						if (cell && typeof cell.Value !== "undefined") {
							cell.Value = value;
							return true;
						}
					} catch (e) {}
					return false;
				}
				function getValue(cell) {
					try {
						if (cell && typeof cell.GetValue === "function") return cell.GetValue();
					} catch (e) {}
					try {
						if (cell && typeof cell.Value !== "undefined") return cell.Value;
					} catch (e) {}
					return "";
				}
				function hasText(value) {
					return String(value == null ? "" : value).replace(/\s+/g, "").length > 0;
				}
				function nextNonEmptyValue(values, startIndex) {
					for (var i = startIndex; i < values.length; i++) {
						if (hasText(values[i])) return { index: i, value: values[i] };
					}
					return null;
				}
				function collectSelectedCells(range) {
					var list = [];
					if (!range) return list;
					try {
						if (typeof range.ForEach === "function") {
							range.ForEach(function(cell) {
								if (cell) list.push(cell);
							});
						}
					} catch (e) {}
					if (!list.length) {
						try {
							if (typeof range.GetCells === "function") {
								var firstCell = range.GetCells(1, 1);
								if (firstCell) list.push(firstCell);
							}
						} catch (e) {}
					}
					try {
						list.sort(function(a, b) {
							var ar = typeof a.Row === "number" ? a.Row : 0;
							var br = typeof b.Row === "number" ? b.Row : 0;
							var ac = typeof a.Col === "number" ? a.Col : 0;
							var bc = typeof b.Col === "number" ? b.Col : 0;
							return (ar - br) || (ac - bc);
						});
					} catch (e) {}
					return list;
				}
				function hasMergeInfo(target) {
					if (!target) return false;
					var methods = ["IsMerged", "IsMerge", "GetMerge", "GetMergeArea", "GetMergedRange", "GetMergeCells"];
					for (var i = 0; i < methods.length; i++) {
						try {
							if (typeof target[methods[i]] === "function") {
								var result = target[methods[i]]();
								if (result) return true;
							}
						} catch (e) {}
					}
					return false;
				}
				function getMergeRange(target) {
					if (!target) return null;
					var methods = ["GetMergeArea", "GetMergedRange", "GetMergeCells", "GetMerge"];
					for (var i = 0; i < methods.length; i++) {
						try {
							if (typeof target[methods[i]] === "function") {
								var result = target[methods[i]]();
								if (result && typeof result === "object") return result;
							}
						} catch (e) {}
					}
					return null;
				}
				function isArray(value) {
					return Object.prototype.toString.call(value) === "[object Array]";
				}
				function isSingleMergedSelection(range, cells) {
					if (!range) return false;
					try {
						var value = typeof range.GetValue === "function" ? range.GetValue() : null;
						if (value !== null && !isArray(value) && hasMergeInfo(range)) return true;
						if (cells && cells.length > 1 && value !== null && !isArray(value)) return true;
					} catch (e) {}
					try {
						var mergeRange = getMergeRange(range);
						if (mergeRange && getRangeAddress(mergeRange) === getRangeAddress(range)) return true;
					} catch (e) {}
					return false;
				}
				function setFirstCellValue(range, ws, value) {
					try {
						if (range && typeof range.GetCells === "function") {
							var firstCell = range.GetCells(1, 1);
							if (setValue(firstCell, value)) return true;
						}
					} catch (e) {}
					try {
						var address = getFirstCellAddress(getRangeAddress(range));
						if (address && ws && typeof ws.GetRange === "function") {
							var cell = ws.GetRange(address);
							if (setValue(cell, value)) return true;
						}
					} catch (e) {}
					return setValue(range, value);
				}
				function getLogicalCellKey(cell) {
					var mergeRange = getMergeRange(cell);
					var mergeAddress = getRangeAddress(mergeRange);
					if (mergeAddress) return "merge:" + mergeAddress;
					return "cell:" + getCellAddress(cell);
				}
				function setLogicalCellValue(cell, ws, value) {
					var mergeRange = getMergeRange(cell);
					if (mergeRange) return setFirstCellValue(mergeRange, ws, value);
					return setValue(cell, value);
				}
				function getLogicalCellValue(cell) {
					var mergeRange = getMergeRange(cell);
					if (mergeRange) {
						try {
							if (typeof mergeRange.GetCells === "function") return getValue(mergeRange.GetCells(1, 1));
						} catch (e) {}
						return getValue(mergeRange);
					}
					return getValue(cell);
				}
				var ws = Api.GetActiveSheet();
				var selection = null;
				try {
					if (typeof Api.GetSelection === "function") selection = Api.GetSelection();
				} catch (e) {}
				if (!selection && ws && typeof ws.GetSelection === "function") {
					try {
						selection = ws.GetSelection();
					} catch (e) {}
				}
				if (!ws || !selection) return false;
				var cells = collectSelectedCells(selection);
				var values = Asc.scope.translatorCellValues || [];
				var fullValue = Asc.scope.translatorCellValue || "";
				if (isSingleMergedSelection(selection, cells)) {
					return setFirstCellValue(selection, ws, fullValue);
				}
				if (cells.length > 1) {
					var valueIndex = 0;
					var writtenCount = 0;
					var seen = {};
					for (var i = 0; i < cells.length && valueIndex < values.length; i++) {
						var cellKey = getLogicalCellKey(cells[i]);
						if (cellKey && seen[cellKey]) continue;
						if (cellKey) seen[cellKey] = true;
						if (!hasText(getLogicalCellValue(cells[i]))) continue;
						var translatedValue = nextNonEmptyValue(values, valueIndex);
						if (!translatedValue) break;
						if (setLogicalCellValue(cells[i], ws, translatedValue.value)) {
							writtenCount++;
							valueIndex = translatedValue.index + 1;
						}
					}
					return writtenCount > 0;
				}
				try {
					if (setFirstCellValue(selection, ws, fullValue)) return true;
				} catch (e) {}
				try {
					if (setValue(selection, fullValue)) {
						return true;
					}
				} catch (e) {}
				return false;
			}, false, true, function() {
				finish();
			});
			setTimeout(finish, 10000);
		}

		if (window.Asc.plugin.info.editorType === "cell") {
			setCellValueOnly();
			return;
		}
		if (window.Asc.plugin.info.editorType !== "word") {
			pastePlainText();
			return;
		}

		Asc.scope.translatorReplaceArr = parseTranslatedParagraphs(translatedTxt);
		Asc.scope.translatorReplaceSelectAll = !!(options && options.selectAll);
		Asc.scope.translatorReplaceExpectedCount = selectionParagraphCount || 0;
		window.Asc.plugin.callCommand(function() {
			var doc = Api.GetDocument();
			if (Asc.scope.translatorReplaceSelectAll && doc) {
				var count = doc.GetElementsCount();
				var range = doc.GetRange(0, count);
				if (range && typeof range.Select === "function") {
					range.Select();
				}
			}
			var selectedCount = 0;
			try {
				var selectedRange = doc && doc.GetRangeBySelect ? doc.GetRangeBySelect() : null;
				var selectedParagraphs = selectedRange && selectedRange.GetAllParagraphs ? selectedRange.GetAllParagraphs() : null;
				selectedCount = selectedParagraphs ? selectedParagraphs.length : 0;
			} catch (e) {}
			if (!selectedCount && Asc.scope.translatorReplaceSelectAll && doc && typeof doc.GetAllParagraphs === "function") {
				try {
					var allParagraphs = doc.GetAllParagraphs() || [];
					selectedCount = allParagraphs.length;
				} catch (e) {}
			}
			var expectedCount = Asc.scope.translatorReplaceExpectedCount || 0;
			if (expectedCount > selectedCount) {
				selectedCount = expectedCount;
			}
			var replaceArr = Asc.scope.translatorReplaceArr || [];
			if (selectedCount > 0 && replaceArr.length !== selectedCount) {
				if (replaceArr.length < selectedCount) {
					while (replaceArr.length < selectedCount) replaceArr.push("");
				} else if (selectedCount === 1) {
					replaceArr = [replaceArr.join("\n")];
				} else {
					var fitted = replaceArr.slice(0, selectedCount - 1);
					fitted.push(replaceArr.slice(selectedCount - 1).join("\n"));
					replaceArr = fitted;
				}
			}
			Asc.scope.translatorReplaceArr = replaceArr;
			if (typeof Api.ReplaceTextSmart === "function") {
				Api.ReplaceTextSmart(Asc.scope.translatorReplaceArr);
				return true;
			}
			return false;
		}, false, true, function(result) {
			// ReplaceTextSmart 执行成功时返回 true，但某些版本可能返回 undefined。
			// 只要不是显式的 false，都视为成功。
			if (result !== false) {
				finish();
			} else {
				pastePlainText();
			}
		});
		setTimeout(finish, 10000);
	}

	function checkInternetExplorer(){
		var rv = -1;
		if (window.navigator.appName == 'Microsoft Internet Explorer') {
			const ua = window.navigator.userAgent;
			const re = new RegExp('MSIE ([0-9]{1,}[\.0-9]{0,})');
			if (re.exec(ua) != null) {
				rv = parseFloat(RegExp.$1);
			}
		} else if (window.navigator.appName == 'Netscape') {
			const ua = window.navigator.userAgent;
			const re = new RegExp('Trident/.*rv:([0-9]{1,}[\.0-9]{0,})');

			if (re.exec(ua) != null) {
				rv = parseFloat(RegExp.$1);
			}
		}
		return rv !== -1;
	};

	function showMessage(message) {
		document.getElementById("iframe_parent").innerHTML = "<h4 id='h4' style='margin:5px'>" + message + "</h4>";
	};

	window.Asc.plugin.button = function(id)
	{
		this.executeCommand("close", "");
	};

	window.onresize = function()
	{
		ifr && ifr.contentWindow && ifr.contentWindow.postMessage("update_scroll", '*');
	};

	window.Asc.plugin.onExternalMouseUp = function()
	{
		var evt = document.createEvent("MouseEvents");
		evt.initMouseEvent("mouseup", true, true, window, 1, 0, 0, 0, 0,
			false, false, false, false, 0, null);

		document.dispatchEvent(evt);
	};

	window.Asc.plugin.onTranslate = function()
	{
		var field = document.getElementById("h4");
		if (field)
			field.innerHTML = window.Asc.plugin.tr(field.innerText);

		translated = window.Asc.plugin.tr('Select Language');
	};
	window.Asc.plugin.onThemeChanged = function(theme)
	{
		window.Asc.plugin.onThemeChangedBase(theme);
		var style = document.getElementsByTagName('head')[0].lastChild;
		if (ifr && ifr.contentWindow)
			setTimeout( function() { ifr.contentDocument && ifr.contentWindow.postMessage({type: 'themeChanged', theme: theme, style: style.innerHTML}, '*' ) } ,600 );
	};
	
})(window, undefined);


