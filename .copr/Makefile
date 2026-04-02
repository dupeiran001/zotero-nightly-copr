.PHONY: srpm

ZOTERO_REPO = https://github.com/zotero/zotero.git

srpm:
	dnf install -y git git-lfs nodejs npm perl python3 curl wget rsync rpm-build
	LATEST_TAG=$$(git ls-remote --tags --sort=-v:refname $(ZOTERO_REPO) '[0-9]*' | grep -v '\^{}' | head -1 | sed 's|.*/||') && \
	echo "Latest tag: $$LATEST_TAG" && \
	./build_srpm.sh "$(ZOTERO_REPO)" "$$LATEST_TAG" "$(outdir)"
