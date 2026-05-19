"""RAG Engine — Retrieval-Augmented Generation pipeline.

This module is NOT wired into the live API flow.  It is scaffolding for future
integration with a local food/nutrition dataset (database.json).

Usage once a database.json is placed next to this file:

    from rag.rag_engine import get_rag_chain
    chain = get_rag_chain()
    if chain:
        result = chain.invoke({"query": "Calories in a chocolate crepe?"})

Previous version issues fixed here:
  1. Module-level open("database.json") crashed on import when the file was absent.
  2. Deprecated import paths:
       langchain.vectorstores        → langchain_community.vectorstores
       langchain.embeddings.openai   → langchain_openai
       langchain.chat_models         → langchain_openai
       langchain.schema.Document     → langchain_core.documents
  3. All now lazily initialised — the chain is only built on first call.
"""

import json
import os
import warnings
from typing import Optional

# Module-level cache — built once, reused on subsequent calls.
_rag_chain = None
_init_attempted = False


def get_rag_chain():
    """Return the RAG chain, building it on first call.

    Returns None (with a warning) when required dependencies or
    ``database.json`` are unavailable so the rest of the app keeps running.
    """
    global _rag_chain, _init_attempted

    if _init_attempted:
        return _rag_chain          # Return cached result (may be None)
    _init_attempted = True

    db_path = os.path.join(os.path.dirname(__file__), "database.json")
    if not os.path.exists(db_path):
        warnings.warn(
            f"RAG engine: database.json not found at {db_path}. "
            "The RAG pipeline will not be available until you add the file.",
            stacklevel=2,
        )
        return None

    try:
        # Updated imports — these packages must be in requirements.txt:
        #   langchain-community, langchain-openai
        from langchain_community.vectorstores import FAISS
        from langchain_openai import OpenAIEmbeddings, ChatOpenAI
        from langchain.chains import RetrievalQA
        from langchain_core.documents import Document

        with open(db_path, encoding="utf-8") as f:
            dataset = json.load(f)

        documents = [Document(page_content=json.dumps(item)) for item in dataset]

        embeddings = OpenAIEmbeddings()
        vectorstore = FAISS.from_documents(documents, embeddings)
        retriever   = vectorstore.as_retriever(search_kwargs={"k": 2})

        llm = ChatOpenAI(temperature=0)
        _rag_chain = RetrievalQA.from_chain_type(
            llm=llm,
            retriever=retriever,
            chain_type="stuff",
            return_source_documents=False,
        )
        return _rag_chain

    except ImportError as exc:
        warnings.warn(
            f"RAG engine: missing dependency — {exc}. "
            "Install langchain-community, langchain-openai, and faiss-cpu.",
            stacklevel=2,
        )
        return None
    except Exception as exc:
        warnings.warn(
            f"RAG engine: failed to initialise — {exc}.",
            stacklevel=2,
        )
        return None
