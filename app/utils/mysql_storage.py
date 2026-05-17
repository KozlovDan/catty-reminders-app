"""
This module handles the persistence layer for the app using MySQL.
"""

# --------------------------------------------------------------------------------
# Imports
# --------------------------------------------------------------------------------

import time

from app.utils.exceptions import ForbiddenException, NotFoundException

from mysql import connector
from mysql.connector import errorcode
from pydantic import BaseModel
from typing import List, Optional


# --------------------------------------------------------------------------------
# Models
# --------------------------------------------------------------------------------

class ReminderItem(BaseModel):
  id: int
  list_id: int
  description: str
  completed: bool


class ReminderList(BaseModel):
  id: int
  owner: str
  name: str


class SelectedList(BaseModel):
  id: int
  owner: str
  name: str
  items: List[ReminderItem]


# --------------------------------------------------------------------------------
# MySQLStorage Class
# --------------------------------------------------------------------------------

class MySQLStorage:

  def __init__(self, owner: str, db_config: dict) -> None:
    self.owner = owner
    self.db_config = db_config
    self.db_name = db_config['database']
    self.conn = self._connect_with_retry()
    self.cursor = self.conn.cursor(dictionary=True)
    self._create_tables()


  def _connect_with_retry(self):
    last_error = None

    for _ in range(30):
      try:
        return connector.connect(**self.db_config)
      except connector.Error as err:
        last_error = err
        if err.errno == errorcode.ER_BAD_DB_ERROR:
          self._create_database()
          continue
        time.sleep(1)

    raise last_error


  def _create_database(self) -> None:
    temp_config = self.db_config.copy()
    temp_config.pop('database', None)

    conn = connector.connect(**temp_config)
    cursor = conn.cursor()
    cursor.execute(f"CREATE DATABASE IF NOT EXISTS `{self.db_name}` DEFAULT CHARACTER SET 'utf8mb4'")
    cursor.close()
    conn.close()


  def _create_tables(self) -> None:
    tables = [
      (
        'reminder_lists',
        """
        CREATE TABLE IF NOT EXISTS reminder_lists (
          id INT NOT NULL AUTO_INCREMENT,
          owner VARCHAR(255) NOT NULL,
          name VARCHAR(255) NOT NULL,
          PRIMARY KEY (id)
        ) ENGINE=InnoDB
        """,
      ),
      (
        'reminder_items',
        """
        CREATE TABLE IF NOT EXISTS reminder_items (
          id INT NOT NULL AUTO_INCREMENT,
          list_id INT NOT NULL,
          description TEXT NOT NULL,
          completed BOOLEAN NOT NULL DEFAULT 0,
          PRIMARY KEY (id),
          CONSTRAINT fk_reminder_items_list
            FOREIGN KEY (list_id)
            REFERENCES reminder_lists (id)
            ON DELETE CASCADE
        ) ENGINE=InnoDB
        """,
      ),
      (
        'selected_lists',
        """
        CREATE TABLE IF NOT EXISTS selected_lists (
          owner VARCHAR(255) NOT NULL,
          list_id INT,
          PRIMARY KEY (owner),
          CONSTRAINT fk_selected_lists_list
            FOREIGN KEY (list_id)
            REFERENCES reminder_lists (id)
            ON DELETE SET NULL
        ) ENGINE=InnoDB
        """,
      ),
    ]

    for _, statement in tables:
      self.cursor.execute(statement)


  def close(self) -> None:
    self.cursor.close()
    self.conn.close()


  # Private Methods

  def _get_raw_list(self, list_id: int) -> dict:
    self.cursor.execute("SELECT * FROM reminder_lists WHERE id = %s", (list_id,))
    reminder_list = self.cursor.fetchone()

    if not reminder_list:
      raise NotFoundException()
    if reminder_list['owner'] != self.owner:
      raise ForbiddenException()

    return reminder_list


  def _get_raw_item(self, item_id: int) -> dict:
    self.cursor.execute("SELECT * FROM reminder_items WHERE id = %s", (item_id,))
    item = self.cursor.fetchone()

    if not item:
      raise NotFoundException()

    self._verify_list_exists(item['list_id'])
    return item


  def _verify_list_exists(self, list_id: int) -> None:
    self._get_raw_list(list_id)


  def _verify_item_exists(self, item_id: int) -> None:
    self._get_raw_item(item_id)


  # Reminder Lists

  def create_list(self, name: str) -> int:
    self.cursor.execute(
      "INSERT INTO reminder_lists (name, owner) VALUES (%s, %s)",
      (name, self.owner),
    )
    self.conn.commit()
    return self.cursor.lastrowid


  def delete_list(self, list_id: int) -> None:
    self._verify_list_exists(list_id)
    self.cursor.execute("DELETE FROM reminder_lists WHERE id = %s", (list_id,))
    self.conn.commit()


  def delete_lists(self) -> None:
    for rem_list in self.get_lists():
      self.delete_list(rem_list.id)


  def get_list(self, list_id: int) -> ReminderList:
    return ReminderList(**self._get_raw_list(list_id))


  def get_lists(self) -> List[ReminderList]:
    self.cursor.execute("SELECT * FROM reminder_lists WHERE owner = %s", (self.owner,))
    return [ReminderList(**row) for row in self.cursor.fetchall()]


  def update_list_name(self, list_id: int, new_name: str) -> None:
    self._verify_list_exists(list_id)
    self.cursor.execute(
      "UPDATE reminder_lists SET name = %s WHERE id = %s",
      (new_name, list_id),
    )
    self.conn.commit()


  # Reminder Items

  def add_item(self, list_id: int, description: str) -> int:
    self._verify_list_exists(list_id)
    self.cursor.execute(
      "INSERT INTO reminder_items (list_id, description, completed) VALUES (%s, %s, %s)",
      (list_id, description, False),
    )
    self.conn.commit()
    return self.cursor.lastrowid


  def delete_item(self, item_id: int) -> None:
    self._verify_item_exists(item_id)
    self.cursor.execute("DELETE FROM reminder_items WHERE id = %s", (item_id,))
    self.conn.commit()


  def get_item(self, item_id: int) -> ReminderItem:
    return ReminderItem(**self._get_raw_item(item_id))


  def get_items(self, list_id: int) -> List[ReminderItem]:
    self._verify_list_exists(list_id)
    self.cursor.execute("SELECT * FROM reminder_items WHERE list_id = %s", (list_id,))
    return [ReminderItem(**row) for row in self.cursor.fetchall()]


  def strike_item(self, item_id: int) -> None:
    item = self._get_raw_item(item_id)
    self.cursor.execute(
      "UPDATE reminder_items SET completed = %s WHERE id = %s",
      (not item['completed'], item_id),
    )
    self.conn.commit()


  def update_item_description(self, item_id: int, new_description: str) -> None:
    self._verify_item_exists(item_id)
    self.cursor.execute(
      "UPDATE reminder_items SET description = %s WHERE id = %s",
      (new_description, item_id),
    )
    self.conn.commit()


  # Selected Lists

  def get_selected_list_id(self) -> Optional[int]:
    self.cursor.execute("SELECT list_id FROM selected_lists WHERE owner = %s", (self.owner,))
    selected_list = self.cursor.fetchone()

    if not selected_list:
      return None

    return selected_list['list_id']


  def get_selected_list(self) -> Optional[SelectedList]:
    list_id = self.get_selected_list_id()
    if list_id is None:
      return None

    try:
      reminder_list = self.get_list(list_id)
      reminder_items = self.get_items(list_id)
    except NotFoundException:
      self.set_selected_list(None)
      return None

    return SelectedList(
      id=reminder_list.id,
      owner=reminder_list.owner,
      name=reminder_list.name,
      items=reminder_items,
    )


  def set_selected_list(self, list_id: Optional[int]) -> None:
    self.cursor.execute(
      """
      INSERT INTO selected_lists (owner, list_id)
      VALUES (%s, %s)
      ON DUPLICATE KEY UPDATE list_id = %s
      """,
      (self.owner, list_id, list_id),
    )
    self.conn.commit()


  def reset_selected_after_delete(self, deleted_id: int) -> None:
    selected_list_id = self.get_selected_list_id()

    if selected_list_id == deleted_id:
      reminder_lists = self.get_lists()
      list_id = reminder_lists[0].id if reminder_lists else None
      self.set_selected_list(list_id)
