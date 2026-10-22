"""a meeting's agenda, and the AI suggestion it was saved from

Revision ID: 0003
Revises: 0002
Create Date: 2026-10-22
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # What the user saved: {"items": [...], "action_items": [...]}.
    op.add_column("meetings", sa.Column("agenda", postgresql.JSONB(), nullable=True))
    # What the model suggested, with the model and prompt version. The
    # difference from `agenda` is the parser's quality signal.
    op.add_column("meetings", sa.Column("ai_suggestion", postgresql.JSONB(), nullable=True))


def downgrade() -> None:
    op.drop_column("meetings", "ai_suggestion")
    op.drop_column("meetings", "agenda")
